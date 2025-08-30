#!/bin/bash

echo "🚀 Setting up Jenkins Container with all necessary tools..."

# Stop and remove existing container if exists
echo "🛑 Stopping existing Jenkins container..."
docker stop jenkins-new 2>/dev/null || true
docker rm jenkins-new 2>/dev/null || true

# Create Jenkins container with all necessary tools
echo "🐳 Creating Jenkins container with tools..."
docker run -d \
  --name jenkins-new \
  -p 7001:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/local/bin/kubectl:/usr/local/bin/kubectl \
  -v /home/always/.kube:/home/always/.kube \
  jenkins/jenkins:lts-jdk17

# Wait for container to start
echo "⏳ Waiting for container to start..."
sleep 10

# Install system packages
echo "📦 Installing system packages..."
docker exec --user root jenkins-new apt-get update
docker exec --user root jenkins-new apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  curl \
  wget \
  git \
  vim \
  unzip

# Install Python packages
echo "🐍 Installing Python packages..."
docker exec --user root jenkins-new python3 -m pip install --upgrade pip
docker exec --user root jenkins-new python3 -m pip install \
  pytest \
  pytest-cov \
  requests \
  fastapi \
  uvicorn \
  torch \
  torchvision \
  opencv-python \
  pillow \
  numpy

# Install Docker client
echo "🐳 Installing Docker client..."
docker exec --user root jenkins-new curl -fsSL https://get.docker.com -o get-docker.sh
docker exec --user root jenkins-new sh get-docker.sh --dry-run
docker exec --user root jenkins-new curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
docker exec --user root jenkins-new chmod +x /usr/local/bin/docker-compose

# Add jenkins user to docker group
echo "👤 Adding jenkins user to docker group..."
docker exec --user root jenkins-new usermod -aG docker jenkins

# Install kubectl
echo "☸️ Installing kubectl..."
docker exec --user root jenkins-new curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
docker exec --user root jenkins-new chmod +x kubectl
docker exec --user root jenkins-new mv kubectl /usr/local/bin/

# Verify installations
echo "✅ Verifying installations..."
echo "Python3: $(docker exec jenkins-new python3 --version)"
echo "Pip3: $(docker exec jenkins-new pip3 --version)"
echo "Docker: $(docker exec jenkins-new docker --version)"
echo "Kubectl: $(docker exec jenkins-new kubectl version --client --short)"

echo "🎉 Jenkins container setup completed!"
echo "🌐 Access Jenkins at: http://localhost:7001"
echo "🔑 Initial password: $(docker exec jenkins-new cat /var/jenkins_home/secrets/initialAdminPassword)"
