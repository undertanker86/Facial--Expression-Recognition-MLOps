#!/bin/bash

echo "🔧 Quick fix for Jenkins tools..."

# Check if Jenkins container is running
if ! docker ps | grep -q jenkins-new; then
    echo "❌ Jenkins container is not running"
    exit 1
fi

echo "✅ Jenkins container is running"

# Install Python packages using apt (system packages)
echo "🐍 Installing Python packages via apt..."
docker exec --user root jenkins-new apt-get update
docker exec --user root jenkins-new apt-get install -y \
    python3-numpy \
    python3-opencv \
    python3-pil \
    python3-pytest \
    python3-requests \
    python3-fastapi \
    python3-uvicorn \
    python3-torch \
    python3-httpx \
    python3-starlette \
    python3-prometheus-client \
    python3-opentelemetry-api \
    python3-opentelemetry-sdk

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
echo "Torch: $(docker exec jenkins-new python3 -c 'import torch; print("✅ Torch installed")' 2>/dev/null || echo "❌ Torch not found")"
echo "Httpx: $(docker exec jenkins-new python3 -c 'import httpx; print("✅ Httpx installed")' 2>/dev/null || echo "❌ Httpx not found")"
echo "Docker: $(docker exec jenkins-new docker --version 2>/dev/null || echo "❌ Docker not found")"

echo "🎉 Quick fix completed!"
echo "💡 Now you can retry the pipeline"
