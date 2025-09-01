#!/bin/bash

set -euo pipefail

# ------------------------------
# Configurable variables
# ------------------------------
CONTAINER_NAME="jenkins-new"
HOST_HTTP_PORT="7001"          # Host port mapped to Jenkins 8080
HOST_AGENT_PORT="50000"
JENKINS_IMAGE="jenkins/jenkins:lts-jdk17"

echo "🚀 Starting simplified Jenkins setup..."

# ------------------------------
# Preflight checks
# ------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker is not installed or not in PATH" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker daemon is not running or not accessible for this user" >&2
  exit 1
fi

# ------------------------------
# Create/Reset container
# ------------------------------
echo "🛑 Removing any existing Jenkins container (${CONTAINER_NAME})..."
docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true

echo "🐳 Creating Jenkins container with Docker socket mount..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${HOST_HTTP_PORT}:8080" \
  -p "${HOST_AGENT_PORT}:50000" \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${JENKINS_IMAGE}"

echo "⏳ Waiting 10s for the container to initialize..."
sleep 10

# ------------------------------
# Install system and Python packages in container
# ------------------------------
echo "📦 Installing base packages inside container..."
docker exec --user root "${CONTAINER_NAME}" apt-get update -y
docker exec --user root "${CONTAINER_NAME}" apt-get install -y \
  python3 python3-pip python3-venv \
  curl wget git vim unzip

echo "🐍 Installing Python packages inside container..."
docker exec --user root "${CONTAINER_NAME}" python3 -m pip install --no-cache-dir --upgrade pip --break-system-packages
docker exec --user root "${CONTAINER_NAME}" python3 -m pip install --no-cache-dir --break-system-packages \
  pytest pytest-cov requests fastapi uvicorn \
  torch torchvision opencv-python pillow numpy \
  httpx starlette prometheus-client

# ------------------------------
# Docker client inside container
# ------------------------------
echo "🐳 Installing Docker client inside container..."
docker exec --user root "${CONTAINER_NAME}" bash -lc 'curl -fsSL https://get.docker.com -o /tmp/get-docker.sh && sh /tmp/get-docker.sh'

echo "👤 Adding jenkins user to docker group and setting socket perms..."
docker exec --user root "${CONTAINER_NAME}" usermod -aG docker jenkins
docker exec --user root "${CONTAINER_NAME}" bash -lc 'if [ -S /var/run/docker.sock ]; then chmod 666 /var/run/docker.sock; fi'

echo "✅ Verifying core tools inside container..."
docker exec "${CONTAINER_NAME}" python3 --version || true
docker exec "${CONTAINER_NAME}" pip3 --version || true
docker exec "${CONTAINER_NAME}" docker --version || true

# ------------------------------
# Prepare Jenkins environment
# ------------------------------
echo "🔐 Fixing ownership/permissions for Jenkins home..."
docker exec --user root "${CONTAINER_NAME}" chown -R jenkins:jenkins /var/jenkins_home
docker exec --user root "${CONTAINER_NAME}" chmod -R 755 /var/jenkins_home

echo "🔁 Restarting container to apply docker group changes..."
docker restart "${CONTAINER_NAME}" >/dev/null

echo "⏳ Waiting for Jenkins UI to be reachable on http://localhost:${HOST_HTTP_PORT} ..."
for i in {1..60}; do
  if curl -fsS "http://localhost:${HOST_HTTP_PORT}" >/dev/null 2>&1; then
    break
  fi
  echo "   ... waiting (${i})"
  sleep 5
done

echo "✅ Jenkins UI should be reachable at http://localhost:${HOST_HTTP_PORT}"

echo "🔑 Reading initial admin password..."
INITIAL_PASSWORD="$(docker exec "${CONTAINER_NAME}" cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true)"
if [ -z "${INITIAL_PASSWORD}" ]; then
  echo "❌ Could not read initial admin password. Jenkins may still be initializing." >&2
else
  echo "🔑 Initial admin password: ${INITIAL_PASSWORD}"
fi

echo "📝 Creating .bashrc and environment for jenkins user..."
docker exec "${CONTAINER_NAME}" bash -lc 'cat > /var/jenkins_home/.bashrc << EOF
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games
export PYTHONPATH=/var/jenkins_home/workspace
export DOCKER_HOST=unix:///var/run/docker.sock
alias python=python3
alias pip=pip3
EOF'

echo "🧪 Creating and running tool verification script..."
docker exec "${CONTAINER_NAME}" bash -lc 'cat > /var/jenkins_home/test_setup.py << "PYEOF"
#!/usr/bin/env python3
import subprocess

def test_tools():
    tools = ["python3", "pip3", "docker"]
    results = {}
    for tool in tools:
        try:
            out = subprocess.run([tool, "--version"], capture_output=True, text=True, timeout=10)
            results[tool] = "✅ " + (out.stdout.strip() or out.stderr.strip())
        except Exception as e:
            results[tool] = "❌ " + str(e)
    for tool, status in results.items():
        print(f"{tool}: {status}")

if __name__ == "__main__":
    test_tools()
PYEOF'

docker exec "${CONTAINER_NAME}" python3 /var/jenkins_home/test_setup.py || true

cat <<SUMMARY

🎉 Jenkins setup completed!
🌐 Open: http://localhost:${HOST_HTTP_PORT}
🔑 Initial Password: ${INITIAL_PASSWORD:-<pending>}

Next steps (in Jenkins UI):
1) Complete initial setup and install suggested plugins
2) Add DockerHub credentials with ID: dockerhub-credentials
3) Create a Pipeline job pointing to this repo (Jenkinsfile present)

Tip: The container has Docker and Python toolchain ready.
SUMMARY

exit 0


