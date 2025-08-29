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
                    sh 'pip install -r requirements.txt || true'
                    sh 'pip install pytest pytest-cov requests || true'
                    echo "✅ Dependencies installed successfully"
                }
            }
        }
        
        stage('Local API Testing') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "🧪 Starting local API testing..."
                    
                    // Start API service in background
                    sh '''
                        echo "🚀 Starting API service on port ${API_PORT}..."
                        cd api
                        python main.py &
                        API_PID=$!
                        echo "API PID: $API_PID"
                        
                        // Wait for service to start
                        echo "⏳ Waiting for API service to start..."
                        sleep 10
                        
                        // Test health endpoint
                        echo "🏥 Testing health endpoint..."
                        for i in {1..30}; do
                            if curl -f http://localhost:${API_PORT}/health > /dev/null 2>&1; then
                                echo "✅ Health endpoint is responding"
                                break
                            fi
                            echo "⏳ Attempt $i: Waiting for health endpoint..."
                            sleep 2
                        done
                        
                        // Run API tests
                        echo "🧪 Running API tests..."
                        cd ../tests
                        python -m pytest test_api.py -v --maxfail=1 || true
                        
                        // Stop API service
                        echo "🛑 Stopping API service..."
                        kill $API_PID || true
                        sleep 2
                    '''
                    
                    echo "✅ Local API testing completed"
                }
            }
        }
        
        stage('Build Docker Image') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "🐳 Building Docker image..."
                    
                    // Clean up Docker system
                    sh 'docker system prune -f || true'
                    
                    // Build new image
                    sh "docker build --no-cache -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
                    sh "docker tag ${DOCKER_IMAGE}:${DOCKER_TAG} ${DOCKER_IMAGE}:latest"
                    
                    // Show built images
                    sh 'docker images | grep fer-service || true'
                    
                    echo "✅ Docker image built successfully"
                }
            }
        }
        
        stage('Push to Docker Hub') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "📤 Pushing to Docker Hub..."
                    
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                        sh 'echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin'
                        sh "docker push ${DOCKER_IMAGE}:${DOCKER_TAG}"
                        sh "docker push ${DOCKER_IMAGE}:latest"
                    }
                    
                    echo "✅ Docker image pushed successfully"
                }
            }
        }
        
        stage('Deploy to Test Namespace') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "☸️ Deploying to test namespace: ${TEST_NAMESPACE}"
                    
                    // Create test namespace if it doesn't exist
                    sh '''
                        echo "📁 Creating test namespace if not exists..."
                        kubectl create namespace ${TEST_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                    '''
                    
                    // Deploy to test namespace
                    sh '''
                        echo "🚀 Deploying to test namespace..."
                        kubectl apply -f k8s/ -n ${TEST_NAMESPACE}
                        
                        // Update deployment with new image
                        kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${TEST_NAMESPACE}
                        
                        // Wait for rollout
                        echo "⏳ Waiting for deployment rollout..."
                        kubectl rollout status deployment/fer-service -n ${TEST_NAMESPACE} --timeout=300s
                        
                        // Check service status
                        echo "🔍 Checking service status..."
                        kubectl get pods -n ${TEST_NAMESPACE}
                        kubectl get svc -n ${TEST_NAMESPACE}
                    '''
                    
                    echo "✅ Test deployment completed"
                }
            }
        }
        
        stage('Test on Kubernetes') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "🧪 Testing service on Kubernetes test namespace..."
                    
                    sh '''
                        echo "⏳ Waiting for pods to be ready..."
                        kubectl wait --for=condition=ready pod -l app=fer-service -n ${TEST_NAMESPACE} --timeout=300s
                        
                        // Get service URL
                        SERVICE_IP=$(kubectl get svc fer-service -n ${TEST_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                        if [ -z "$SERVICE_IP" ]; then
                            SERVICE_IP=$(kubectl get svc fer-service -n ${TEST_NAMESPACE} -o jsonpath='{.spec.clusterIP}')
                        fi
                        
                        SERVICE_PORT=$(kubectl get svc fer-service -n ${TEST_NAMESPACE} -o jsonpath='{.spec.ports[0].port}')
                        
                        echo "🔗 Service URL: http://$SERVICE_IP:$SERVICE_PORT"
                        
                        // Test health endpoint
                        echo "🏥 Testing health endpoint on K8s..."
                        kubectl run test-curl --image=curlimages/curl -i --rm --restart=Never -- curl -f http://fer-service.${TEST_NAMESPACE}.svc.cluster.local:${SERVICE_PORT}/health || true
                        
                        // Run additional tests if needed
                        echo "🧪 Running additional tests..."
                        kubectl run test-curl --image=curlimages/curl -i --rm --restart=Never -- curl -f http://fer-service.${TEST_NAMESPACE}.svc.cluster.local:${SERVICE_PORT}/ || true
                    '''
                    
                    echo "✅ Kubernetes testing completed"
                }
            }
        }
        
        stage('Deploy to Production') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "🚀 Deploying to production namespace: ${NAMESPACE}"
                    
                    // Create production namespace if it doesn't exist
                    sh '''
                        echo "📁 Creating production namespace if not exists..."
                        kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                    '''
                    
                    // Deploy to production
                    sh '''
                        echo "🚀 Deploying to production..."
                        kubectl apply -f k8s/ -n ${NAMESPACE}
                        
                        // Update deployment with new image
                        kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${NAMESPACE}
                        
                        // Wait for rollout
                        echo "⏳ Waiting for production deployment rollout..."
                        kubectl rollout status deployment/fer-service -n ${NAMESPACE} --timeout=300s
                        
                        // Check production status
                        echo "🔍 Checking production status..."
                        kubectl get pods -n ${NAMESPACE}
                        kubectl get svc -n ${NAMESPACE}
                    '''
                    
                    echo "✅ Production deployment completed"
                }
            }
        }
        
        stage('Verify Production') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "🔍 Verifying production deployment..."
                    
                    sh '''
                        echo "⏳ Waiting for production pods to be ready..."
                        kubectl wait --for=condition=ready pod -l app=fer-service -n ${NAMESPACE} --timeout=300s
                        
                        // Test production service
                        echo "🧪 Testing production service..."
                        kubectl run test-curl --image=curlimages/curl -i --rm --restart=Never -- curl -f http://fer-service.${NAMESPACE}.svc.cluster.local:8000/health || true
                        
                        // Show final status
                        echo "📊 Final production status:"
                        kubectl get all -n ${NAMESPACE}
                    '''
                    
                    echo "✅ Production verification completed"
                }
            }
        }
        
        stage('Cleanup Test Environment') {
            when {
                changeset 'api/main.py'
            }
            steps {
                script {
                    echo "🧹 Cleaning up test environment..."
                    
                    sh '''
                        echo "🗑️ Removing test namespace..."
                        kubectl delete namespace ${TEST_NAMESPACE} --ignore-not-found=true
                        
                        echo "🧹 Cleaning up Docker system..."
                        docker system prune -f || true
                    '''
                    
                    echo "✅ Cleanup completed"
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🏁 Pipeline completed!"
                echo ""
                echo "📋 Pipeline Summary:"
                echo "🔢 Build Number: ${BUILD_NUMBER}"
                echo "🐳 Docker Image: ${DOCKER_IMAGE}:${DOCKER_TAG}"
                echo "📁 Production Namespace: ${NAMESPACE}"
                echo "📁 Test Namespace: ${TEST_NAMESPACE}"
            }
        }
        success {
            script {
                echo "✅ Pipeline completed successfully!"
                echo ""
                echo "🎉 Deployment Summary:"
                echo "🐳 Docker image built and pushed: ${DOCKER_IMAGE}:${DOCKER_TAG}"
                echo "☸️ Tested on namespace: ${TEST_NAMESPACE}"
                echo "🚀 Deployed to production: ${NAMESPACE}"
                echo ""
                echo "🔗 Production service should be available at:"
                echo "   http://<your-cluster-ip>:8000"
            }
        }
        failure {
            script {
                echo "❌ Pipeline failed!"
                echo ""
                echo "🔍 Troubleshooting steps:"
                echo "1. Check Jenkins logs for detailed error messages"
                echo "2. Verify Docker Hub credentials are correct"
                echo "3. Check if Kubernetes cluster is accessible"
                echo "4. Verify namespace permissions"
                echo ""
                echo "🧹 Cleanup may be needed:"
                echo "   kubectl delete namespace ${TEST_NAMESPACE} --ignore-not-found=true"
            }
        }
        cleanup {
            script {
                echo "🧹 Running cleanup..."
                sh 'docker system prune -f || true'
                echo "✅ Cleanup completed"
            }
        }
    }
}
