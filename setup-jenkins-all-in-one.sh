#!/bin/bash

# =============================================================================
# FER Project - Jenkins All-in-One Setup Script
# =============================================================================
# This script sets up Jenkins container with all necessary dependencies
# for the Facial Expression Recognition (FER) project CI/CD pipeline.
# =============================================================================

set -e  # Exit on any error

echo "🚀 Starting Jenkins All-in-One Setup for FER Project"
echo "=================================================="

# Configuration
JENKINS_CONTAINER_NAME="jenkins-fer"
JENKINS_PORT="7001"
JENKINS_VOLUME="jenkins_home_fer"
DOCKER_SOCKET="/var/run/docker.sock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is running
check_docker() {
    print_status "Checking Docker status..."
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    print_success "Docker is running"
}

# Stop and remove existing Jenkins container if it exists
cleanup_existing_container() {
    print_status "Cleaning up existing Jenkins container..."
    
    if docker ps -a --format "table {{.Names}}" | grep -q "^${JENKINS_CONTAINER_NAME}$"; then
        print_status "Stopping existing Jenkins container..."
        docker stop ${JENKINS_CONTAINER_NAME} || true
        print_status "Removing existing Jenkins container..."
        docker rm ${JENKINS_CONTAINER_NAME} || true
        print_success "Existing container cleaned up"
    else
        print_status "No existing Jenkins container found"
    fi
}

# Create Jenkins volume if it doesn't exist
create_jenkins_volume() {
    print_status "Creating Jenkins volume..."
    if ! docker volume ls --format "table {{.Name}}" | grep -q "^${JENKINS_VOLUME}$"; then
        docker volume create ${JENKINS_VOLUME}
        print_success "Jenkins volume created: ${JENKINS_VOLUME}"
    else
        print_status "Jenkins volume already exists: ${JENKINS_VOLUME}"
    fi
}

# Start Jenkins container with comprehensive setup
start_jenkins_container() {
    print_status "Starting Jenkins container with comprehensive setup..."
    
    docker run -d \
        --name ${JENKINS_CONTAINER_NAME} \
        --restart=unless-stopped \
        -p ${JENKINS_PORT}:8080 \
        -v ${JENKINS_VOLUME}:/var/jenkins_home \
        -v ${DOCKER_SOCKET}:/var/run/docker.sock \
        -v /usr/bin/docker:/usr/bin/docker:ro \
        --group-add $(stat -c %g ${DOCKER_SOCKET}) \
        jenkins/jenkins:lts-jdk17
    
    if [ $? -eq 0 ]; then
        print_success "Jenkins container started successfully"
    else
        print_error "Failed to start Jenkins container"
        exit 1
    fi
}

# Wait for Jenkins to be ready
wait_for_jenkins() {
    print_status "Waiting for Jenkins to be ready..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:${JENKINS_PORT}/login >/dev/null 2>&1; then
            print_success "Jenkins is ready!"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts: Jenkins not ready yet, waiting 5 seconds..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_error "Jenkins failed to start within expected time"
    return 1
}

# Install system dependencies in Jenkins container
install_system_dependencies() {
    print_status "Installing system dependencies in Jenkins container..."
    
    docker exec ${JENKINS_CONTAINER_NAME} bash -c "
        apt-get update && \
        apt-get install -y \
            curl \
            wget \
            git \
            unzip \
            build-essential \
            libgl1-mesa-glx \
            libglib2.0-0 \
            libsm6 \
            libxext6 \
            libxrender-dev \
            libgomp1 \
            libjpeg-dev \
            libpng-dev \
            libgtk-3-dev \
            python3-dev \
            python3-pip \
            python3-venv \
            software-properties-common \
            apt-transport-https \
            ca-certificates \
            gnupg \
            lsb-release
    "
    
    if [ $? -eq 0 ]; then
        print_success "System dependencies installed successfully"
    else
        print_error "Failed to install system dependencies"
        exit 1
    fi
}

# Install Python dependencies in Jenkins container
install_python_dependencies() {
    print_status "Installing Python dependencies in Jenkins container..."
    
    docker exec ${JENKINS_CONTAINER_NAME} bash -c "
        pip3 install --break-system-packages \
            numpy \
            opencv-python \
            pillow \
            torch \
            torchvision \
            fastapi \
            uvicorn \
            pytest \
            requests \
            httpx \
            starlette \
            prometheus-client \
            opentelemetry-api \
            opentelemetry-sdk \
            opentelemetry-instrumentation-fastapi \
            opentelemetry-exporter-jaeger \
            opentelemetry-instrumentation-logging \
            opentelemetry-instrumentation-system-metrics \
            opentelemetry-exporter-otlp-proto-http \
            python-multipart
    "
    
    if [ $? -eq 0 ]; then
        print_success "Python dependencies installed successfully"
    else
        print_error "Failed to install Python dependencies"
        exit 1
    fi
}

# Test Python packages in Jenkins container
test_python_packages() {
    print_status "Testing Python packages in Jenkins container..."
    
    docker exec ${JENKINS_CONTAINER_NAME} python3 -c "
        import sys
        packages = [
            'numpy', 'cv2', 'PIL', 'torch', 'torchvision', 
            'fastapi', 'uvicorn', 'pytest', 'requests', 
            'httpx', 'starlette', 'prometheus_client',
            'opentelemetry', 'opentelemetry.instrumentation.fastapi',
            'opentelemetry.exporter.jaeger', 'opentelemetry.instrumentation.logging',
            'opentelemetry.instrumentation.system_metrics', 'opentelemetry.exporter.otlp',
            'multipart'
        ]
        
        failed = []
        for package in packages:
            try:
                __import__(package)
                print(f'✅ {package}')
            except ImportError as e:
                print(f'❌ {package}: {e}')
                failed.append(package)
        
        if failed:
            print(f'\\n❌ Failed packages: {failed}')
            sys.exit(1)
        else:
            print('\\n✅ All packages imported successfully!')
    "
    
    if [ $? -eq 0 ]; then
        print_success "All Python packages tested successfully"
    else
        print_error "Some Python packages failed to import"
        exit 1
    fi
}

# Test Docker installation in Jenkins container
test_docker_installation() {
    print_status "Testing Docker installation in Jenkins container..."
    
    docker exec ${JENKINS_CONTAINER_NAME} docker --version
    
    if [ $? -eq 0 ]; then
        print_success "Docker is working in Jenkins container"
    else
        print_error "Docker is not working in Jenkins container"
        exit 1
    fi
}

# Get Jenkins initial admin password
get_jenkins_password() {
    print_status "Getting Jenkins initial admin password..."
    
    local password
    password=$(docker exec ${JENKINS_CONTAINER_NAME} cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null)
    
    if [ -n "$password" ]; then
        print_success "Jenkins initial admin password retrieved"
        echo ""
        echo "=================================================="
        echo "🔑 JENKINS INITIAL ADMIN PASSWORD:"
        echo "=================================================="
        echo "$password"
        echo "=================================================="
        echo ""
        echo "🌐 Jenkins UI: http://localhost:${JENKINS_PORT}"
        echo "📝 Use this password to complete Jenkins setup"
        echo "=================================================="
    else
        print_warning "Could not retrieve Jenkins initial admin password"
        print_status "Jenkins UI should be reachable at: http://localhost:${JENKINS_PORT}"
    fi
}

# Main execution
main() {
    echo ""
    print_status "Starting comprehensive Jenkins setup for FER project..."
    echo ""
    
    check_docker
    cleanup_existing_container
    create_jenkins_volume
    start_jenkins_container
    wait_for_jenkins
    install_system_dependencies
    install_python_dependencies
    test_python_packages
    test_docker_installation
    get_jenkins_password
    
    echo ""
    print_success "🎉 Jenkins setup completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Open Jenkins UI: http://localhost:${JENKINS_PORT}"
    echo "2. Use the initial admin password shown above"
    echo "3. Install suggested plugins"
    echo "4. Create admin user"
    echo "5. Create DockerHub credentials (ID: dockerhub-credentials)"
    echo "6. Create Pipeline job from SCM"
    echo "7. Point to your GitHub repository"
    echo ""
    print_status "Jenkins container name: ${JENKINS_CONTAINER_NAME}"
    print_status "Jenkins volume: ${JENKINS_VOLUME}"
    print_status "Jenkins port: ${JENKINS_PORT}"
    echo ""
}

# Run main function
main "$@"
