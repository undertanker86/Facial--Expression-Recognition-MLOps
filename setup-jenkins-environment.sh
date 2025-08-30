#!/bin/bash

echo "🔧 Setting up Jenkins Environment and Configuration..."

# Check if Jenkins container is running
if ! docker ps | grep -q jenkins-new; then
    echo "❌ Jenkins container is not running. Please run setup-jenkins-container.sh first."
    exit 1
fi

echo "✅ Jenkins container is running"

# Wait for Jenkins to be ready
echo "⏳ Waiting for Jenkins to be ready..."
while ! curl -s http://localhost:7001 > /dev/null; do
    echo "Waiting for Jenkins to start..."
    sleep 5
done

echo "✅ Jenkins is accessible"

# Get initial admin password
INITIAL_PASSWORD=$(docker exec jenkins-new cat /var/jenkins_home/secrets/initialAdminPassword)
echo "🔑 Initial admin password: $INITIAL_PASSWORD"

# Create Jenkins CLI jar directory
echo "📁 Setting up Jenkins CLI..."
docker exec jenkins-new mkdir -p /var/jenkins_home/war/WEB-INF/lib

# Download Jenkins CLI jar if not exists
if ! docker exec jenkins-new test -f /var/jenkins_home/war/WEB-INF/lib/jenkins-cli.jar; then
    echo "⬇️ Downloading Jenkins CLI..."
    docker exec jenkins-new wget -O /var/jenkins_home/war/WEB-INF/lib/jenkins-cli.jar \
        http://localhost:8080/jnlpJars/jenkins-cli.jar
fi

# Create Jenkins home directory structure
echo "📂 Creating Jenkins directory structure..."
docker exec jenkins-new mkdir -p /var/jenkins_home/workspace
docker exec jenkins-new mkdir -p /var/jenkins_home/jobs
docker exec jenkins-new mkdir -p /var/jenkins_home/plugins

# Set proper permissions
echo "🔐 Setting proper permissions..."
docker exec --user root jenkins-new chown -R jenkins:jenkins /var/jenkins_home
docker exec --user root jenkins-new chmod -R 755 /var/jenkins_home

# Create .bashrc for jenkins user
echo "📝 Setting up environment for jenkins user..."
docker exec jenkins-new bash -c 'cat > /var/jenkins_home/.bashrc << EOF
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games
export PYTHONPATH=/var/jenkins_home/workspace
export DOCKER_HOST=unix:///var/run/docker.sock
export KUBECONFIG=/home/always/.kube/config
alias python=python3
alias pip=pip3
EOF'

# Install additional Python packages that might be needed
echo "🐍 Installing additional Python packages..."
docker exec --user root jenkins-new python3 -m pip install \
    pytest-mock \
    pytest-asyncio \
    aiohttp \
    httpx \
    beautifulsoup4 \
    lxml

# Create a simple test script
echo "📝 Creating test script..."
docker exec jenkins-new bash -c 'cat > /var/jenkins_home/test_setup.py << EOF
#!/usr/bin/env python3
import sys
import subprocess

def test_tools():
    tools = ["python3", "pip3", "docker", "kubectl"]
    results = {}
    
    for tool in tools:
        try:
            result = subprocess.run([tool, "--version"], 
                                  capture_output=True, text=True, timeout=10)
            results[tool] = "✅ " + result.stdout.strip()
        except Exception as e:
            results[tool] = "❌ " + str(e)
    
    print("🔧 Tool Status:")
    for tool, status in results.items():
        print(f"  {tool}: {status}")

if __name__ == "__main__":
    test_tools()
EOF'

# Test the setup
echo "🧪 Testing the setup..."
docker exec jenkins-new python3 /var/jenkins_home/test_setup.py

echo ""
echo "🎉 Jenkins Environment Setup Completed!"
echo "🌐 Access Jenkins at: http://localhost:7001"
echo "🔑 Initial password: $INITIAL_PASSWORD"
echo ""
echo "📋 Next steps:"
echo "1. Open Jenkins UI in browser"
echo "2. Complete initial setup"
echo "3. Install suggested plugins"
echo "4. Create admin user"
echo "5. Configure GitHub webhook with tunnel URL"
echo ""
echo "💡 To test the setup, run: docker exec jenkins-new python3 /var/jenkins_home/test_setup.py"
