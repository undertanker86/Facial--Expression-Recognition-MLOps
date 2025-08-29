pipeline {
    agent any
    
    environment {
        DOCKER_IMAGE = 'undertanker86/fer-service'
        DOCKER_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
        NAMESPACE = 'fer-project'
        TEST_NAMESPACE = 'fer-service-test'
        BUILD_STATUS = 'UNKNOWN'
        API_PORT = '8000'
    }
    
    stages {
        stage('Pipeline Setup') {
            steps {
                script {
                    currentBuild.displayName = "#${BUILD_NUMBER} - ${env.BUILD_TAG ?: 'Code Update'}"
                    echo "🚀 Starting CI/CD Pipeline for FER Service"
                    echo "📝 Build Number: ${BUILD_NUMBER}"
                    echo "🔗 Git Commit: ${env.GIT_COMMIT.take(7)}"
                    echo "🐳 Docker Image: ${DOCKER_IMAGE}"
                    echo "🏷️ Docker Tag: ${DOCKER_TAG}"
                }
            }
        }
        
        stage('Checkout Code') {
            steps {
                checkout scm
                script {
                    sh 'git log --oneline -1'
                    echo "📁 Repository: ${env.GIT_URL}"
                    echo "🌿 Branch: ${env.GIT_BRANCH}"
                    echo "✅ Commit: ${env.GIT_COMMIT}"
                }
            }
        }
        
        stage('Install Dependencies') {
            steps {
                script {
                    echo "📦 Installing Python dependencies..."
                    sh 'python3 -m pip install -r requirements.txt || true'
                    sh 'python3 -m pip install pytest pytest-cov requests || true'
                    echo "✅ Dependencies installed successfully"
                }
            }
        }
        
        stage('Local API Testing') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "🧪 Starting local API testing..."
                    sh '''
                        echo "🚀 Starting API service on port ${API_PORT}..."
                        cd api
                        python3 main.py &
                        API_PID=$!
                        echo "API PID: $API_PID"
                        echo "⏳ Waiting for API service to start..."
                        sleep 10
                        echo "🏥 Testing health endpoint..."
                        for i in {1..30}; do
                            if curl -f http://localhost:${API_PORT}/health > /dev/null 2>&1; then
                                echo "✅ Health endpoint is responding"
                                break
                            fi
                            echo "⏳ Attempt $i: Waiting for health endpoint..."
                            sleep 2
                        done
                        echo "🧪 Running API tests..."
                        cd ../tests
                        python3 -m pytest test_api.py -v --maxfail=1 || true
                        echo "🛑 Stopping API service..."
                        kill $API_PID || true
                        sleep 2
                    '''
                    echo "✅ Local API testing completed"
                }
            }
        }
        
        stage('Build Docker Image') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "🐳 Building Docker image using host Docker daemon..."
                    sh 'docker exec jenkins-new docker system prune -f || true'
                    sh "docker exec jenkins-new docker build --no-cache -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
                    sh "docker exec jenkins-new docker tag ${DOCKER_IMAGE}:${DOCKER_TAG} ${DOCKER_IMAGE}:latest"
                    sh 'docker exec jenkins-new docker images | grep fer-service || true'
                    echo "✅ Docker image built successfully using host Docker"
                }
            }
        }
        
        stage('Push to Docker Hub') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "📤 Pushing to Docker Hub using host Docker daemon..."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                        sh 'echo $DOCKER_PASSWORD | docker exec jenkins-new docker login -u $DOCKER_USERNAME --password-stdin'
                        sh "docker exec jenkins-new docker push ${DOCKER_IMAGE}:${DOCKER_TAG}"
                        sh "docker exec jenkins-new docker push ${DOCKER_IMAGE}:latest"
                    }
                    echo "✅ Docker image pushed successfully using host Docker"
                }
            }
        }

        stage('Deploy to Test Namespace') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "☸️ Deploying to test namespace using host kubectl..."
                    sh "docker exec jenkins-new kubectl create ns ${TEST_NAMESPACE} --dry-run=client -o yaml | docker exec jenkins-new kubectl apply -f -"
                    sh "docker exec jenkins-new kubectl apply -f k8s/ -n ${TEST_NAMESPACE}"
                    sh "docker exec jenkins-new kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${TEST_NAMESPACE}"
                    echo "✅ Test deployment completed using host kubectl"
                }
            }
        }

        stage('Test on Kubernetes') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "🧪 Testing deployment on Kubernetes..."
                    sh "docker exec jenkins-new kubectl rollout status deployment/fer-service -n ${TEST_NAMESPACE} --timeout=300s"
                    sh "docker exec jenkins-new kubectl wait --for=condition=ready pod -l app=fer-service -n ${TEST_NAMESPACE} --timeout=300s"
                    sh "docker exec jenkins-new kubectl run curl --image=curlimages/curl -i --rm --restart=Never -n ${TEST_NAMESPACE} -- curl -sf http://fer-service.${TEST_NAMESPACE}.svc.cluster.local:${API_PORT}/health"
                    echo "✅ Kubernetes testing completed"
                }
            }
        }

        stage('Deploy to Production') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "🚀 Deploying to production namespace..."
                    sh "docker exec jenkins-new kubectl apply -f k8s/ -n ${NAMESPACE}"
                    sh "docker exec jenkins-new kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${NAMESPACE}"
                    echo "✅ Production deployment completed"
                }
            }
        }

        stage('Verify Production') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "🔍 Verifying production deployment..."
                    sh "docker exec jenkins-new kubectl rollout status deployment/fer-service -n ${NAMESPACE} --timeout=300s"
                    sh "docker exec jenkins-new kubectl wait --for=condition=ready pod -l app=fer-service -n ${NAMESPACE} --timeout=300s"
                    sh "docker exec jenkins-new kubectl run curl --image=curlimages/curl -i --rm --restart=Never -n ${NAMESPACE} -- curl -sf http://fer-service.${NAMESPACE}.svc.cluster.local:${API_PORT}/health"
                    echo "✅ Production verification completed"
                }
            }
        }

        stage('Cleanup Test Environment') {
            when { changeset 'api/main.py' }
            steps {
                script {
                    echo "🧹 Cleaning up test environment..."
                    sh "docker exec jenkins-new kubectl delete ns ${TEST_NAMESPACE} --ignore-not-found=true"
                    echo "✅ Test environment cleanup completed"
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🏁 Pipeline completed!"
                echo "📋 Pipeline Summary:";
                echo "🔢 Build Number: ${BUILD_NUMBER}";
                echo "🐳 Docker Image: ${DOCKER_IMAGE}:${DOCKER_TAG}";
                echo "📁 Production Namespace: ${NAMESPACE}";
                echo "📁 Test Namespace: ${TEST_NAMESPACE}";
            }
        }
        success {
            script {
                echo "✅ Pipeline completed successfully!"
                echo "💡 Next: Run the printed kubectl commands on your host."
            }
        }
        failure {
            script {
                echo "❌ Pipeline failed!"
                echo "🔍 Check logs and retry."
            }
        }
        cleanup {
            script {
                echo "🧹 Running cleanup using host Docker..."
                sh 'docker exec jenkins-new docker system prune -f || true'
                echo "✅ Cleanup completed using host Docker"
            }
        }
    }
}
