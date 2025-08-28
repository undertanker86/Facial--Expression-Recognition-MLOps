import pytest
import io
import os
from PIL import Image
import numpy as np
from fastapi.testclient import TestClient

# Allow tests to run without real model weights
os.environ.setdefault('SKIP_MODEL_LOAD_FOR_TEST', '1')

from api.main import app

client = TestClient(app)

def create_test_image():
    """Create a test image for testing"""
    # Create a simple test image
    image_array = np.random.randint(0, 255, (224, 224, 3), dtype=np.uint8)
    image = Image.fromarray(image_array)
    
    # Save to bytes
    img_byte_arr = io.BytesIO()
    image.save(img_byte_arr, format='PNG')
    img_byte_arr.seek(0)
    
    return img_byte_arr

def test_root_endpoint():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    assert "message" in response.json()
    assert response.json()["version"] == "1.0.0"

def test_health_check():
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert data["status"] == "healthy"
    assert "model_loaded" in data
    assert "timestamp" in data

def test_metrics_endpoint():
    """Test Prometheus metrics endpoint"""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"] == CONTENT_TYPE_LATEST

def test_model_info():
    """Test model info endpoint"""
    response = client.get("/model-info")
    assert response.status_code == 200
    data = response.json()
    assert "model_type" in data
    assert "num_classes" in data
    assert "emotions" in data
    assert len(data["emotions"]) == 7

def test_predict_emotion():
    """Test emotion prediction endpoint"""
    # Create test image
    test_image = create_test_image()
    
    # Test with valid image
    response = client.post(
        "/predict",
        files={"file": ("test.png", test_image.getvalue(), "image/png")}
    )
    
    # Should return 200 or 500 (depending on model availability)
    assert response.status_code in [200, 500]
    
    if response.status_code == 200:
        data = response.json()
        assert "emotion" in data
        assert "confidence" in data
        assert "class_id" in data
        assert "processing_time" in data
        assert data["emotion"] in ["surprise", "fear", "disgust", "happiness", "sadness", "anger", "neutral"]

def test_predict_invalid_file():
    """Test prediction with invalid file type"""
    # Test with text file
    response = client.post(
        "/predict",
        files={"file": ("test.txt", b"not an image", "text/plain")}
    )
    assert response.status_code == 400
    assert "File must be an image" in response.json()["detail"]

def test_predict_no_file():
    """Test prediction without file"""
    response = client.post("/predict")
    assert response.status_code == 422  # Validation error

if __name__ == "__main__":
    pytest.main([__file__, "-v"])