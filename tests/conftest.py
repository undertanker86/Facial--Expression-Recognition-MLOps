import pytest
import os
import sys
from unittest.mock import MagicMock
import numpy as np

# Add project root to Python path
project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, project_root)

# Mock dependencies that are not available during testing
@pytest.fixture(autouse=True)
def mock_dependencies():
    """Mock dependencies that are not available during testing"""
    # Mock torch
    mock_torch = MagicMock()
    mock_torch.nn = MagicMock()
    mock_torch.load = MagicMock()
    mock_torch.no_grad = MagicMock()
    
    # Mock model
    mock_model = MagicMock()
    mock_model.parameters = MagicMock(return_value=[MagicMock(numel=MagicMock(return_value=1000000))])
    mock_model.eval = MagicMock()
    mock_model.to = MagicMock(return_value=mock_model)
    
    # Mock cv2
    mock_cv2 = MagicMock()
    mock_cv2.imdecode = MagicMock(return_value=np.random.randint(0, 255, (112, 112, 3), dtype=np.uint8))
    mock_cv2.resize = MagicMock(return_value=np.random.randint(0, 255, (112, 112, 3), dtype=np.uint8))
    
    # Mock PIL with proper Image class
    mock_pil = MagicMock()
    mock_image = MagicMock()
    mock_image.fromarray = MagicMock(return_value=mock_image)
    mock_image.save = MagicMock()
    mock_image.seek = MagicMock()
    mock_image.getvalue = MagicMock(return_value=b"fake_image_data")
    mock_pil.Image = mock_image
    
    # Patch modules BEFORE any imports
    sys.modules['torch'] = mock_torch
    sys.modules['cv2'] = mock_cv2
    sys.modules['PIL'] = mock_pil
    
    # Set environment variables
    os.environ['SKIP_MODEL_LOAD_FOR_TEST'] = '1'
    os.environ['OTEL_EXPORTER_OTLP_ENDPOINT'] = 'http://localhost:4318/v1/traces'
    os.environ['JAEGER_HOST'] = 'localhost'
    os.environ['JAEGER_PORT'] = '6831'
    
    # Inject mock model into api.main module
    import api.main
    api.main.model = mock_model
    
    yield
    
    # Cleanup
    if 'torch' in sys.modules:
        del sys.modules['torch']
    if 'cv2' in sys.modules:
        del sys.modules['cv2']
    if 'PIL' in sys.modules:
        del sys.modules['PIL']
