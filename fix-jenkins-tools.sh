't #!/bin/bash

echo "🔧 Quick fix for Jenkins tools..."

# Check if Jenkins container is running
if ! docker ps | grep -q jenkins-new; then
    echo "❌ Jenkins container is not running"
    exit 1
fi

echo "✅ Jenkins container is running"

# Install system dependencies for OpenCV and other packages
echo "🔧 Installing system dependencies..."
docker exec --user root jenkins-new apt-get update
docker exec --user root jenkins-new apt-get install -y \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    python3-pip \
    python3-dev \
    build-essential \
    pkg-config \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libxvidcore-dev \
    libx264-dev \
    libgtk-3-dev \
    libatlas-base-dev \
    gfortran

# Install Python packages using pip
echo "🐍 Installing Python packages via pip..."
docker exec --user root jenkins-new python3 -m pip install --no-cache-dir --upgrade pip --break-system-packages
docker exec --user root jenkins-new python3 -m pip install --no-cache-dir --break-system-packages \
    numpy \
    opencv-python \
    pillow \
    pytest \
    pytest-cov \
    requests \
    fastapi \
    uvicorn \
    torch \
    torchvision \
    httpx \
    starlette \
    prometheus-client \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-instrumentation-fastapi \
    opentelemetry-exporter-jaeger

# Install Docker client properly
echo "🐳 Installing Docker client..."
docker exec --user root jenkins-new curl -fsSL https://get.docker.com -o get-docker.sh
docker exec --user root jenkins-new sh get-docker.sh

# Add jenkins user to docker group and fix permissions
echo "👤 Adding jenkins user to docker group..."
docker exec --user root jenkins-new usermod -aG docker jenkins
docker exec --user root jenkins-new chmod 666 /var/run/docker.sock

# Restart Jenkins container to apply group changes
echo "🔄 Restarting Jenkins container to apply group changes..."
docker restart jenkins-new

# Wait for Jenkins to be ready
echo "⏳ Waiting for Jenkins to be ready..."
sleep 15

# Test installations
echo "🧪 Testing installations..."
echo "Python3: $(docker exec jenkins-new python3 --version)"
echo "Numpy: $(docker exec jenkins-new python3 -c 'import numpy; print("✅ Numpy installed")' 2>/dev/null || echo "❌ Numpy not found")"
echo "OpenCV: $(docker exec jenkins-new python3 -c 'import cv2; print("✅ OpenCV installed")' 2>/dev/null || echo "❌ OpenCV not found")"
echo "Torch: $(docker exec jenkins-new python3 -c 'import torch; print("✅ Torch installed")' 2>/dev/null || echo "❌ Torch not found")"
echo "FastAPI: $(docker exec jenkins-new python3 -c 'import fastapi; print("✅ FastAPI installed")' 2>/dev/null || echo "❌ FastAPI not found")"
echo "Pytest: $(docker exec jenkins-new python3 -c 'import pytest; print("✅ Pytest installed")' 2>/dev/null || echo "❌ Pytest not found")"
echo "Httpx: $(docker exec jenkins-new python3 -c 'import httpx; print("✅ Httpx installed")' 2>/dev/null || echo "❌ Httpx not found")"
echo "Docker: $(docker exec jenkins-new docker --version 2>/dev/null || echo "❌ Docker not found")"

echo "🎉 Quick fix completed!"
echo "💡 Now you can retry the pipeline"
