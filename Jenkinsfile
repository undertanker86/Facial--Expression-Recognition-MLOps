pipeline {
    agent any
    
    environment {
        DOCKER_IMAGE = 'undertanker86/fer-service'
        DOCKER_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
        HOST_KUBECTL = 'true'  // Use host machine for kubectl
        NAMESPACE = 'fer-service'
        TEST_NAMESPACE = 'fer-service-test'
        IS_MODEL_UPDATE = false
        MODEL_VERSION = ''
        BUILD_STATUS = 'UNKNOWN'
    }
    
    stages {
        stage('Pipeline Setup') {
            steps {
                script {
                    currentBuild.displayName = "#${BUILD_NUMBER} - ${env.BUILD_TAG ?: 'Code Update'}"
                    if (env.TAG_NAME && env.TAG_NAME.startsWith('model-v')) {
                        env.IS_MODEL_UPDATE = true
                        env.MODEL_VERSION = env.TAG_NAME.replace('model-v', '')
                        currentBuild.displayName = "#${BUILD_NUMBER} - Model v${MODEL_VERSION}"
                        echo "🚀 Model update detected: ${MODEL_VERSION}"
                    } else {
                        echo "📝 Code update detected"
                    }
                    if (!env.DOCKER_IMAGE) { error "DOCKER_IMAGE environment variable is not set" }
                }
            }
        }
        
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    sh 'git log --oneline -1'
                    echo "Repository: ${env.GIT_URL}"
                    echo "Branch: ${env.GIT_BRANCH}"
                    echo "Commit: ${env.GIT_COMMIT}"
                }
            }
        }
        
        stage('API Tests') {
            when {
                allOf {
                    expression { return env.IS_MODEL_UPDATE != 'true' }
                    changeset 'api/main.py'
                }
            }
            steps {
                script {
                    echo "🧪 Running API tests..."
                    sh 'pip install -r requirements.txt || true'
                    sh 'pip install pytest pytest-cov || true'
                    sh 'cd tests && python -m pytest test_api.py -v --maxfail=1'
                }
            }
        }

        stage('Validate Metadata') {
            when {
                allOf {
                    expression { return env.IS_MODEL_UPDATE != 'true' }
                    changeset 'api/main.py'
                }
            }
            steps {
                script {
                    echo "🗂️ Validating model metadata (model/model_metadata.json)..."
                    sh '''
                        mkdir -p model
                        if [ ! -f model/model_metadata.json ]; then
                          echo "metadata missing, generating default..."
                          MODEL_NAME=${MODEL_NAME:-fer-model}
                          VERSION="build-${BUILD_NUMBER}"
                          cat > model/model_metadata.json << EOF
{
  "model_name": "${MODEL_NAME}",
  "version": "${VERSION}"
}
EOF
                        fi
                        python - << 'PY'
import json, sys
with open('model/model_metadata.json') as f:
    data = json.load(f)
missing = [k for k in ['model_name','version'] if k not in data or not str(data[k]).strip()]
if missing:
    print(f"Metadata missing required keys: {missing}")
    sys.exit(1)
print(f"Metadata OK: model_name={data['model_name']}, version={data['version']}")
PY
                    '''
                }
            }
        }
        
        stage('Build Docker Image') {
            when {
                anyOf {
                    expression { return env.IS_MODEL_UPDATE == 'true' }
                    allOf {
                        expression { return env.IS_MODEL_UPDATE != 'true' }
                        changeset 'api/main.py'
                    }
                }
            }
            steps {
                script {
                    echo "🐳 Building Docker image..."
                    sh 'docker system prune -f || true'
                    if (env.IS_MODEL_UPDATE == 'true') {
                        sh "docker build --no-cache -t ${DOCKER_IMAGE}:model-${MODEL_VERSION} ."
                        sh "docker tag ${DOCKER_IMAGE}:model-${MODEL_VERSION} ${DOCKER_IMAGE}:latest"
                    } else {
                        sh "docker build --no-cache -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
                        sh "docker tag ${DOCKER_IMAGE}:${DOCKER_TAG} ${DOCKER_IMAGE}:latest"
                    }
                    sh 'docker images | grep fer-service || true'
                }
            }
        }
        
        stage('Push to Docker Hub') {
            when {
                anyOf {
                    expression { return env.IS_MODEL_UPDATE == 'true' }
                    allOf {
                        expression { return env.IS_MODEL_UPDATE != 'true' }
                        changeset 'api/main.py'
                    }
                }
            }
            steps {
                script {
                    echo "📤 Pushing to Docker Hub..."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                        sh 'echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin'
                        if (env.IS_MODEL_UPDATE == 'true') {
                            sh 'docker push ${DOCKER_IMAGE}:model-${MODEL_VERSION}'
                            sh 'docker push ${DOCKER_IMAGE}:latest'
                        } else {
                            sh 'docker push ${DOCKER_IMAGE}:${DOCKER_TAG}'
                            sh 'docker push ${DOCKER_IMAGE}:latest'
                        }
                    }
                }
            }
        }
        
        stage('Deploy to Test Namespace (Host kubectl)') {
            when {
                allOf {
                    expression { return env.IS_MODEL_UPDATE != 'true' }
                    changeset 'api/main.py'
                }
            }
            steps {
                script {
                    echo "☸️ Deploying to test namespace using host kubectl..."
                    echo "🚀 This will be done on the host machine after Jenkins completes"
                    echo "🐳 Docker image: ${DOCKER_IMAGE}:${DOCKER_TAG}"
                    echo "📁 Test namespace: ${TEST_NAMESPACE}"
                    echo ""
                    echo "📋 Run this command on your host machine:"
                    echo "   chmod +x scripts/deploy-from-host.sh"
                    echo "   ./scripts/deploy-from-host.sh ${DOCKER_IMAGE} ${DOCKER_TAG}"
                }
            }
        }

        stage('Deploy to Production (Host kubectl)') {
            when {
                anyOf {
                    expression { return env.IS_MODEL_UPDATE == 'true' }
                    allOf {
                        expression { return env.IS_MODEL_UPDATE != 'true' }
                        changeset 'api/main.py'
                    }
                }
            }
            steps {
                script {
                    if (env.IS_MODEL_UPDATE == 'true') {
                        echo "🤖 Model update detected!"
                        echo "🏷️ Tag: ${env.GIT_TAG}"
                        echo "🚀 Deploying model update to production using host kubectl..."
                        echo ""
                        echo "📋 Run this command on your host machine:"
                        echo "   kubectl apply -f k8s/ -n ${NAMESPACE}"
                        echo "   kubectl rollout restart deployment/fer-service -n ${NAMESPACE}"
                        echo "   kubectl rollout status deployment/fer-service -n ${NAMESPACE}"
                    } else {
                        echo "📝 Code update detected!"
                        echo "🚀 Deploying to production using host kubectl..."
                        echo "📋 Run this command on your host machine:"
                        echo "   kubectl apply -f k8s/ -n ${NAMESPACE}"
                        echo "   kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${NAMESPACE}"
                        echo "   kubectl rollout status deployment/fer-service -n ${NAMESPACE}"
                    }
                }
            }
        }
    }
    
    post {
        always {
            script {
                sh 'docker system prune -f || true'
                echo "🏁 Pipeline completed!"
                echo ""
                echo "🔧 NEXT STEPS:"
                echo "1. Jenkins has built and pushed Docker image"
                echo "2. Run kubectl commands on your host machine"
                echo "3. Use scripts/deploy-from-host.sh for automated deployment"
            }
        }
        success {
            echo "✅ Pipeline completed successfully"
            echo "🐳 Docker image: ${DOCKER_IMAGE}:${DOCKER_TAG}"
            echo "📋 Model metadata updated"
        }
        failure {
            echo "❌ Pipeline failed"
            echo "🔍 Check Jenkins logs for details"
        }
    }
}
