import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""
import time
import io
import numpy as np
import cv2
from PIL import Image
import torch
import torch.nn.functional as F
import torch.nn as nn
from fastapi import FastAPI, File, UploadFile, HTTPException, Response, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace, metrics
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import ConsoleMetricExporter, PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.instrumentation.system_metrics import SystemMetricsInstrumentor
# CHANGED: Switch from EfficientFaceNet to MobileFaceNet for 7-class prediction
from src.mobilefacenet import MobileFaceNet  # was: from src.efficientfacenet import efficient_face
import torch.nn as nn  # added for head replacement

# Force CPU device
DEVICE = torch.device("cpu")

# Initialize FastAPI app
app = FastAPI(
    title="FER API - Facial Expression Recognition",
    description="API for emotion detection using MobileFaceNet model",  # CHANGED description (touch to trigger CI/CD)
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Setup OpenTelemetry tracing with resource attributes
resource = Resource.create({
    "service.name": os.getenv('OTEL_SERVICE_NAME', 'fer-service'),
    "service.version": os.getenv('OTEL_SERVICE_VERSION', '1.0.0'),
    "deployment.environment": os.getenv('OTEL_DEPLOYMENT_ENVIRONMENT', 'production')
})

# Setup TracerProvider with resource
trace.set_tracer_provider(TracerProvider(resource=resource))

# Use OTLP exporter instead of Jaeger exporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
otlp_exporter = OTLPSpanExporter(
    endpoint=os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://jaeger:4318/v1/traces')
)

trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)

# Setup MeterProvider for metrics
metric_reader = PeriodicExportingMetricReader(ConsoleMetricExporter())
metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[metric_reader]))

# Get tracer and meter
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

# Instrument FastAPI with OpenTelemetry
FastAPIInstrumentor.instrument_app(app)

# Instrument system metrics (without psutil)
SystemMetricsInstrumentor().instrument()

# Prometheus metrics
REQUEST_COUNT = Counter('fer_api_requests_total', 'Total requests to FER API', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('fer_api_request_duration_seconds', 'Request latency in seconds', ['method', 'endpoint'])
PREDICTION_COUNT = Counter('fer_api_predictions_total', 'Total predictions made', ['emotion', 'status'])
MODEL_LOAD_TIME = Histogram('fer_model_load_duration_seconds', 'Model loading time in seconds')
MODEL_INFERENCE_TIME = Histogram('fer_model_inference_duration_seconds', 'Model inference time in seconds')
MODEL_CONFIDENCE = Histogram('fer_model_confidence_score', 'Model confidence scores', ['emotion'])
ACTIVE_REQUESTS = Gauge('fer_active_requests', 'Number of active requests')
MODEL_MEMORY_USAGE = Gauge('fer_model_memory_bytes', 'Model memory usage in bytes')
MODEL_PARAMETERS = Gauge('fer_model_parameters_total', 'Total number of model parameters')

# Initialize MODEL_PARAMETERS to 0
MODEL_PARAMETERS.set(0)

# OpenTelemetry metrics
request_counter = meter.create_counter(
    name="fer_requests_total",
    description="Total number of requests",
    unit="1"
)

request_duration = meter.create_histogram(
    name="fer_request_duration",
    description="Request duration",
    unit="ms"
)

prediction_counter = meter.create_counter(
    name="fer_predictions_total", 
    description="Total number of predictions",
    unit="1"
)

# Emotion mapping
EMOTION_MAPPING = {
    1: 'surprise',
    2: 'fear', 
    3: 'disgust',
    4: 'happiness',
    5: 'sadness',
    6: 'anger',
    7: 'neutral'
}

# Global model variable
model = None

# Allow tests to bypass hard failure on missing weights
_SKIP_MODEL_LOAD_FOR_TEST = os.getenv('SKIP_MODEL_LOAD_FOR_TEST', '0') in ('1', 'true', 'True', 'YES', 'yes')

class _DummyModel(nn.Module):
    def __init__(self, num_classes: int = 7):
        super().__init__()
        self.num_classes = num_classes
    def forward(self, x):  # x: [B, C, H, W]
        return torch.zeros((x.shape[0], self.num_classes), dtype=torch.float32)

def load_model():
    """Load the trained MobileFaceNet model (7 classes)."""  # CHANGED docstring
    global model
    start_time = time.time()
    
    with tracer.start_as_current_span("load_model") as span:
        try:
            span.set_attribute("model.path", os.getenv('MODEL_PATH', '/app/model/best_model_now.pth'))
            span.set_attribute("device", str(DEVICE))
            
            # CHANGED: build MobileFaceNet backbone and 7-class head
            num_classes = 7
            backbone = MobileFaceNet(input_size=[112, 112], embedding_size=136, output_name="GDC")
            # Replace classification head to 7 classes
            backbone.output_layer.linear = nn.Linear(in_features=512, out_features=num_classes, bias=False)
            backbone.output_layer.bn = nn.BatchNorm1d(num_classes)
            model = backbone
            model_path = os.getenv('MODEL_PATH', '/app/model/best_model_now.pth')  # keep same env/path
            
            if os.path.exists(model_path):
                state = torch.load(model_path, map_location=DEVICE)
                # allow loading either flat state_dict or wrapped
                if isinstance(state, dict) and 'state_dict' in state:
                    state = state['state_dict']
                model.load_state_dict(state, strict=False)  # CHANGED: strict=False for compatibility
                span.set_attribute("model.loaded", True)
            else:
                span.set_attribute("model.loaded", False)
                raise FileNotFoundError(f"Model not found at {model_path}")
            
            model.to(DEVICE)
            model.eval()
            
            # Record model metrics
            model_params = sum(p.numel() for p in model.parameters())
            MODEL_PARAMETERS.set(model_params)
            span.set_attribute("model.parameters", model_params)
            
            load_time = time.time() - start_time
            MODEL_LOAD_TIME.observe(load_time)
            span.set_attribute("model.load_time", load_time)
            
            print(f"Model loaded successfully from {model_path} on {DEVICE}")
            return True
            
        except Exception as e:
            span.set_attribute("error", True)
            span.set_attribute("error.message", str(e))
            print(f"Error loading model: {e}")
            return False
    
def preprocess_image(image_bytes: bytes) -> torch.Tensor:
    """Preprocess image for model inference (MobileFaceNet expects 112x112)."""  # CHANGED comment
    with tracer.start_as_current_span("preprocess_image") as span:
        try:
            span.set_attribute("image.size_bytes", len(image_bytes))
            
            # Convert bytes to PIL Image
            image = Image.open(io.BytesIO(image_bytes))
            
            # Convert to RGB if necessary
            if image.mode != 'RGB':
                image = image.convert('RGB')
            
            # CHANGED: Resize to 112x112 for MobileFaceNet
            image = image.resize((112, 112))
            span.set_attribute("image.resized_dimensions", "112x112")
            
            # Convert to numpy array and normalize
            image_array = np.array(image).astype(np.float32) / 255.0
            
            # Convert to tensor and add batch dimension
            image_tensor = torch.from_numpy(image_array).permute(2, 0, 1).unsqueeze(0)
            
            span.set_attribute("tensor.shape", str(image_tensor.shape))
            return image_tensor
            
        except Exception as e:
            span.set_attribute("error", True)
            span.set_attribute("error.message", str(e))
            raise HTTPException(status_code=400, detail=f"Image preprocessing failed: {str(e)}")

@app.on_event("startup")
async def startup_event():
    """Initialize model on startup"""
    with tracer.start_as_current_span("startup") as span:
        if _SKIP_MODEL_LOAD_FOR_TEST:
            # Do not fail pipeline tests if weights are missing
            global model
            model = _DummyModel().to(DEVICE).eval()
            span.set_attribute("startup.success", True)
            span.set_attribute("startup.mode", "dummy")
        else:
            if not load_model():
                span.set_attribute("startup.success", False)
                raise RuntimeError("Failed to load model")
            span.set_attribute("startup.mode", "real")
        span.set_attribute("startup.success", True)

@app.get("/")
async def root():
    """Root endpoint"""
    start_time = time.time()
    
    # Record metrics for root endpoint
    REQUEST_COUNT.labels(method="GET", endpoint="/", status="200").inc()
    REQUEST_LATENCY.labels(method="GET", endpoint="/").observe(time.time() - start_time)
    
    return {"message": "FER API is running", "version": "1.0.0"}

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    start_time = time.time()
    
    # Record metrics for health check
    REQUEST_COUNT.labels(method="GET", endpoint="/health", status="200").inc()
    REQUEST_LATENCY.labels(method="GET", endpoint="/health").observe(time.time() - start_time)
    
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "timestamp": time.time()
    }

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    start_time = time.time()
    
    # Record metrics for metrics endpoint
    REQUEST_COUNT.labels(method="GET", endpoint="/metrics", status="200").inc()
    REQUEST_LATENCY.labels(method="GET", endpoint="/metrics").observe(time.time() - start_time)
    
    try:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": f"Failed to generate metrics: {str(e)}"}
        )

@app.post("/predict")
async def predict_emotion(request: Request, file: UploadFile = File(...)):
    """Predict emotion from uploaded image"""
    start_time = time.time()
    request_id = str(time.time())
    
    # Increment active requests
    ACTIVE_REQUESTS.inc()
    
    with tracer.start_as_current_span("predict_emotion") as span:
        span.set_attribute("request.id", request_id)
        span.set_attribute("file.name", file.filename)
        span.set_attribute("file.content_type", file.content_type)
        
        try:
            # Validate file type
            if not file.content_type.startswith('image/'):
                span.set_attribute("error", True)
                span.set_attribute("error.type", "invalid_file_type")
                raise HTTPException(status_code=400, detail="File must be an image")
            
            # Read image file
            image_bytes = await file.read()
            span.set_attribute("image.size_bytes", len(image_bytes))
            
            # Preprocess image
            input_tensor = preprocess_image(image_bytes).to(DEVICE).float()
            
            # Make prediction
            inference_start = time.time()
            with torch.no_grad():
                outputs = model(input_tensor)
                probabilities = F.softmax(outputs, dim=1)
                predicted_class = torch.argmax(probabilities, dim=1).item()
                confidence = probabilities[0][predicted_class].item()
            
            inference_time = time.time() - inference_start
            MODEL_INFERENCE_TIME.observe(inference_time)
            span.set_attribute("inference.time", inference_time)
            
            # Map class to emotion
            emotion = EMOTION_MAPPING.get(predicted_class + 1, "unknown")
            span.set_attribute("prediction.emotion", emotion)
            span.set_attribute("prediction.confidence", confidence)
            span.set_attribute("prediction.class_id", predicted_class + 1)
            
            # Record metrics
            total_time = time.time() - start_time
            REQUEST_COUNT.labels(method="POST", endpoint="/predict", status="200").inc()
            REQUEST_LATENCY.labels(method="POST", endpoint="/predict").observe(total_time)
            PREDICTION_COUNT.labels(emotion=emotion, status="success").inc()
            MODEL_CONFIDENCE.labels(emotion=emotion).observe(confidence)
            
            # OpenTelemetry metrics
            request_counter.add(1, {"method": "POST", "endpoint": "/predict", "status": "200"})
            request_duration.record(total_time * 1000, {"method": "POST", "endpoint": "/predict"})
            prediction_counter.add(1, {"emotion": emotion, "status": "success"})
            
            # Decrement active requests
            ACTIVE_REQUESTS.dec()
            
            return {
                "emotion": emotion,
                "confidence": round(confidence, 4),
                "class_id": predicted_class + 1,
                "processing_time": round(total_time, 4),
                "inference_time": round(inference_time, 4),
                "request_id": request_id
            }
            
        except Exception as e:
            # Record error metrics
            total_time = time.time() - start_time
            REQUEST_COUNT.labels(method="POST", endpoint="/predict", status="500").inc()
            REQUEST_LATENCY.labels(method="POST", endpoint="/predict").observe(total_time)
            PREDICTION_COUNT.labels(emotion="error", status="failed").inc()
            
            # OpenTelemetry metrics
            request_counter.add(1, {"method": "POST", "endpoint": "/predict", "status": "500"})
            request_duration.record(total_time * 1000, {"method": "POST", "endpoint": "/predict"})
            prediction_counter.add(1, {"emotion": "error", "status": "failed"})
            
            # Decrement active requests
            ACTIVE_REQUESTS.dec()
            
            span.set_attribute("error", True)
            span.set_attribute("error.message", str(e))
            span.set_attribute("error.type", type(e).__name__)
            
            raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

@app.get("/model-info")
async def model_info():
    """Get information about the loaded model"""
    start_time = time.time()
    
    with tracer.start_as_current_span("model_info") as span:
        if model is None:
            span.set_attribute("error", True)
            span.set_attribute("error.message", "Model not loaded")
            
            # Record error metrics
            REQUEST_COUNT.labels(method="GET", endpoint="/model-info", status="500").inc()
            REQUEST_LATENCY.labels(method="GET", endpoint="/model-info").observe(time.time() - start_time)
            
            raise HTTPException(status_code=500, detail="Model not loaded")
        
        model_params = sum(p.numel() for p in model.parameters())
        span.set_attribute("model.parameters", model_params)
        
        # Record success metrics
        REQUEST_COUNT.labels(method="GET", endpoint="/model-info", status="200").inc()
        REQUEST_LATENCY.labels(method="GET", endpoint="/model-info").observe(time.time() - start_time)
        
        return {
            "model_type": "MobileFaceNet",  # CHANGED
            "num_classes": 7,
            "emotions": list(EMOTION_MAPPING.values()),
            "model_parameters": model_params
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)# Test comment for CI/CD trigger
# Test change for CI/CD pipeline
# CI/CD Pipeline Test - Fri Aug 29 12:42:22 PM +07 2025
# Trigger new CI/CD pipeline - Fri Aug 29 12:50:35 PM +07 2025
# trigger build 1756453861
# webhook trigger 1756463264
# test python installation 1756464176
# trigger pipeline 1756464571
# trigger full pipeline 1756465162
