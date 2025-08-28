pipeline {
    agent any
    
    environment {
        DOCKER_IMAGE = 'undertanker86/fer-service'
        DOCKER_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
        KUBECONFIG = '/home/jenkins/.kube/config'
        NAMESPACE = 'fer-project'
        TEST_NAMESPACE = 'fer-project-test'
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
        
        stage('Deploy to Test Namespace') {
            when {
                allOf {
                    expression { return env.IS_MODEL_UPDATE != 'true' }
                    changeset 'api/main.py'
                }
            }
            steps {
                script {
                    echo "☸️ Deploying to test namespace: ${TEST_NAMESPACE}"
                    sh "kubectl get namespace ${TEST_NAMESPACE} || kubectl create namespace ${TEST_NAMESPACE}"

                    // Apply manifests to test namespace by overriding metadata.namespace
                    sh '''
                        for f in k8s/*.yaml; do
                          sed -e "s/namespace: ${NAMESPACE}/namespace: ${TEST_NAMESPACE}/g" "$f" | kubectl apply -n ${TEST_NAMESPACE} -f -
                        done
                    '''

                    // Update image to the newly built tag
                    sh "kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${TEST_NAMESPACE} || true"

                    // Wait rollout and verify
                    sh "kubectl rollout status deployment/fer-service -n ${TEST_NAMESPACE} --timeout=300s"
                    sh "kubectl get pods -n ${TEST_NAMESPACE} -l app=fer-service"
                }
            }
        }
        
        stage('Test Namespace Health Check') {
            when {
                allOf {
                    expression { return env.IS_MODEL_UPDATE != 'true' }
                    changeset 'api/main.py'
                }
            }
            steps {
                script {
                    echo "🏥 Health check on test namespace..."
                    sh '''
                        kubectl get svc -n ${TEST_NAMESPACE} fer-service || true
                        kubectl port-forward -n ${TEST_NAMESPACE} svc/fer-service 8001:8000 &
                        sleep 15
                        curl -f --max-time 20 http://localhost:8001/health
                        curl -s --max-time 20 http://localhost:8001/docs > /dev/null || true
                        pkill -f "kubectl port-forward" || true
                    '''
                }
            }
        }

        stage('Teardown Test Namespace') {
            when {
                allOf {
                    expression { return env.IS_MODEL_UPDATE != 'true' }
                    changeset 'api/main.py'
                }
            }
            steps {
                script {
                    echo "🧹 Tearing down test namespace resources..."
                    // Option A: delete the whole namespace
                    // sh "kubectl delete namespace ${TEST_NAMESPACE} --ignore-not-found=true"
                    // Option B: delete only app resources to keep ns around
                    sh '''
                        for f in k8s/*.yaml; do
                          sed -e "s/namespace: ${NAMESPACE}/namespace: ${TEST_NAMESPACE}/g" "$f" | kubectl delete -n ${TEST_NAMESPACE} -f - --ignore-not-found=true || true
                        done
                    '''
                }
            }
        }

        stage('Deploy to Production Namespace (Code Updates)') {
            when {
                allOf {
                    expression { return env.IS_MODEL_UPDATE != 'true' }
                    changeset 'api/main.py'
                }
            }
            steps {
                script {
                    echo "🚀 Deploying tested image to production namespace: ${NAMESPACE}"
                    sh "kubectl get namespace ${NAMESPACE} || kubectl create namespace ${NAMESPACE}"
                    sh "kubectl apply -f k8s/ -n ${NAMESPACE}"
                    sh "kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${NAMESPACE} || true"
                    sh "kubectl rollout status deployment/fer-service -n ${NAMESPACE} --timeout=300s"
                    sh "kubectl get pods -n ${NAMESPACE} -l app=fer-service"
                }
            }
        }
        
        stage('Deploy to Production Namespace (Model Tags)') {
            when {
                expression { return env.IS_MODEL_UPDATE == 'true' }
            }
            steps {
                script {
                    echo "🚀 Deploying model tag to production: ${NAMESPACE}"
                    sh "kubectl get namespace ${NAMESPACE} || kubectl create namespace ${NAMESPACE}"
                    sh "kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:model-${MODEL_VERSION} -n ${NAMESPACE} || kubectl apply -f k8s/deployment.yaml -n ${NAMESPACE}"
                    sh "kubectl rollout status deployment/fer-service -n ${NAMESPACE} --timeout=300s"
                    sh "kubectl get pods -n ${NAMESPACE} -l app=fer-service"
                }
            }
        }
    }
    
    post {
        always {
            script {
                sh 'docker system prune -f || true'
                sh 'pkill -f "kubectl port-forward" || true'
            }
        }
        success {
            echo "✅ Pipeline completed successfully"
        }
        failure {
            script {
                echo "❌ Pipeline failed, attempting rollback"
                sh "kubectl rollout undo deployment/fer-service -n ${TEST_NAMESPACE} || true"
            }
        }
    }
}
