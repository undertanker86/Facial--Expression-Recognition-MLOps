from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import torch.nn as nn
import torch.nn.functional as F
from typing import List
import torch
from torchvision import transforms
from PIL import Image
import io
import os
import sys
import json

# Ensure project root on sys.path for `src.*` imports when running locally
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

try:
    # Import MobileFaceNet
    from src.mobilefacenet import MobileFaceNet
except Exception as import_err:
    # Defer error to runtime for clearer message
    MobileFaceNet = None  # type: ignore
    _IMPORT_ERROR = import_err
else:
    _IMPORT_ERROR = None

app = FastAPI(title="MobileFaceNet Simple API", version="1.0.0")

# Global model holder
MODEL = None
_FORCE_CPU = os.getenv("MOBILEFACENET_FORCE_CPU", "0") in ("1", "true", "True", "YES", "yes")
DEVICE = torch.device("cpu" if _FORCE_CPU or not torch.cuda.is_available() else "cuda")

# Image preprocessing to 112x112 RGB
preprocess = transforms.Compose([
    transforms.Resize((112, 112)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
])


def load_model(device: torch.device) -> torch.nn.Module:
    """Load MobileFaceNet for 7-class classification (custom head)."""
    num_classes = int(os.getenv("MOBILEFACENET_NUM_CLASSES", "7"))
    # Backbone
    model = MobileFaceNet(input_size=[112, 112], embedding_size=136, output_name="GDC")
    # Replace classification head to 7 classes as your previous setup
    model.output_layer.linear = nn.Linear(in_features=512, out_features=num_classes, bias=False)
    model.output_layer.bn = nn.BatchNorm1d(num_classes)
    model.eval()
    model.to(device)
    # Load weights
    weights_path = os.getenv("MOBILEFACENET_WEIGHTS", "./model/best_model.pth")
    if os.path.isfile(weights_path):
        state = torch.load(weights_path, map_location=device)
        state_dict = state.get("state_dict", state)
        model.load_state_dict(state_dict, strict=False)
    return model


@app.on_event("startup")
async def startup_event():
    global MODEL
    MODEL = load_model(DEVICE)


@app.get("/health")
async def health():
    return {"status": "ok", "device": str(DEVICE)}


class PredictResponse(BaseModel):
    logits: List[float]
    probs: List[float]
    predicted_index: int
    predicted_label: str


@app.post("/predict", response_model=PredictResponse)
async def predict(file: UploadFile = File(...)):
    # Surface import issues clearly
    if _IMPORT_ERROR is not None:
        raise HTTPException(status_code=500, detail=f"Import error: {_IMPORT_ERROR}")
    if MODEL is None:
        raise HTTPException(status_code=500, detail="Model not loaded")
    try:
        content = await file.read()
        image = Image.open(io.BytesIO(content)).convert("RGB")
        with torch.no_grad():
            tensor = preprocess(image).unsqueeze(0).to(DEVICE)
            try:
                logits_tensor = MODEL(tensor)  # [1, num_classes]
            except RuntimeError as ce:
                msg = str(ce)
                if "CUDA error" in msg or "no kernel image" in msg or "device-side" in msg:
                    # Fallback to CPU inference transparently
                    cpu_device = torch.device("cpu")
                    cpu_model = MODEL.to(cpu_device)
                    tensor_cpu = tensor.to(cpu_device)
                    logits_tensor = cpu_model(tensor_cpu)
                else:
                    raise
            logits = logits_tensor.squeeze(0).detach().cpu().float()
            probs = F.softmax(logits, dim=-1)
            idx = int(torch.argmax(probs).item())
            probs_list = probs.tolist()
            logits_list = logits.tolist()
            # Optional labels via env, else numeric
            labels_env = os.getenv("MOBILEFACENET_LABELS", "")
            labels = [s.strip() for s in labels_env.split(",") if s.strip()] if labels_env else [str(i) for i in range(len(probs_list))]
            label = labels[idx] if idx < len(labels) else str(idx)
        return {"logits": logits_list, "probs": probs_list, "predicted_index": idx, "predicted_label": label}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")


@app.get("/info")
async def info():
    """Return basic model and metadata info to help debugging."""
    meta_path = os.path.join(PROJECT_ROOT, "model", "model_metadata.json")
    meta = {}
    if os.path.isfile(meta_path):
        try:
            with open(meta_path, "r") as f:
                meta = json.load(f)
        except Exception:
            meta = {"error": "Failed to parse model_metadata.json"}
    num_classes = int(os.getenv("MOBILEFACENET_NUM_CLASSES", "7"))
    return {
        "device": str(DEVICE),
        "has_model": MODEL is not None,
        "weights_env": os.getenv("MOBILEFACENET_WEIGHTS", ""),
        "num_classes": num_classes,
        "labels": os.getenv("MOBILEFACENET_LABELS", ""),
        "metadata": meta,
    }


# For local run: uvicorn api.main_simple:app --reload --port 8001
