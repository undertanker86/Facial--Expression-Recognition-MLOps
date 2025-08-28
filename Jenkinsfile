pipeline {
    agent any
    
    environment {
        DOCKER_IMAGE = 'undertanker86/fer-service'
        DOCKER_TAG = "${env.BUILD_NUMBER}"
        KUBECONFIG = '/home/jenkins/.kube/config'
        NAMESPACE = 'fer-project'
        IS_MODEL_UPDATE = false
        MODEL_VERSION = ''
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                
                // Kiểm tra xem có phải model update không
                script {
                    if (env.TAG_NAME && env.TAG_NAME.startsWith('model-v')) {
                        env.IS_MODEL_UPDATE = true
                        env.MODEL_VERSION = env.TAG_NAME.replace('model-v', '')
                        echo "🚀 Model update detected: ${MODEL_VERSION}"
                    } else {
                        echo "📝 Code update detected"
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    if (env.IS_MODEL_UPDATE == 'true') {
                        // Build với model mới
                        sh "docker build -t ${DOCKER_IMAGE}:model-${MODEL_VERSION} ."
                        sh "docker tag ${DOCKER_IMAGE}:model-${MODEL_VERSION} ${DOCKER_IMAGE}:latest"
                    } else {
                        // Build bình thường
                        sh "docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
                    }
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                script {
                    sh 'cd tests && python -m pytest test_api.py -v'
                }
            }
        }
        
        stage('Push to Docker Hub') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                        sh 'echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin'
                        
                        if (env.IS_MODEL_UPDATE == 'true') {
                            sh 'docker push ${DOCKER_IMAGE}:model-${MODEL_VERSION}'
                            sh 'docker push ${DOCKER_IMAGE}:latest'
                        } else {
                            sh 'docker push ${DOCKER_IMAGE}:${DOCKER_TAG}'
                            sh 'docker tag ${DOCKER_IMAGE}:${DOCKER_TAG} ${DOCKER_IMAGE}:latest'
                            sh 'docker push ${DOCKER_IMAGE}:latest'
                        }
                    }
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    if (env.IS_MODEL_UPDATE == 'true') {
                        // Deploy model mới
                        echo "🚀 Deploying new model version: ${MODEL_VERSION}"
                        
                        // Update deployment với model mới
                        sh "kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:model-${MODEL_VERSION} -n ${NAMESPACE}"
                        
                        // Wait for rollout
                        sh "kubectl rollout status deployment/fer-service -n ${NAMESPACE}"
                        
                        // Verify deployment
                        sh "kubectl get pods -n ${NAMESPACE} -l app=fer-service"
                        
                        // Log model version
                        sh "kubectl logs -n ${NAMESPACE} -l app=fer-service --tail=20"
                        
                    } else {
                        // Deploy code update bình thường
                        sh "kubectl set image deployment/fer-service fer-service=${DOCKER_IMAGE}:${DOCKER_TAG} -n ${NAMESPACE}"
                        sh "kubectl rollout status deployment/fer-service -n ${NAMESPACE}"
                        sh "kubectl get pods -n ${NAMESPACE} -l app=fer-service"
                    }
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    // Wait for service to be ready
                    sh 'sleep 30'
                    
                    // Check health endpoint
                    sh '''
                        kubectl get svc -n fer-project fer-service
                        kubectl port-forward -n fer-project svc/fer-service 8000:8000 &
                        sleep 10
                        curl -f http://localhost:8000/health || exit 1
                        pkill -f "kubectl port-forward"
                    '''
                }
            }
        }
    }
    
    post {
        always {
            sh 'docker system prune -f'
        }
        success {
            script {
                if (env.IS_MODEL_UPDATE == 'true') {
                    echo "🎉 Model update successful! New model: ${DOCKER_IMAGE}:model-${MODEL_VERSION}"
                    
                    // Update deployment info
                    sh '''
                        echo "Model Update: ${DOCKER_IMAGE}:model-${MODEL_VERSION}" > deployment-info.txt
                        echo "Timestamp: $(date)" >> deployment-info.txt
                        echo "Model Version: ${MODEL_VERSION}" >> deployment-info.txt
                        echo "Tag: ${TAG_NAME}" >> deployment-info.txt
                    '''
                } else {
                    echo "✅ Code deployment successful! Image: ${DOCKER_IMAGE}:${DOCKER_TAG}"
                }
            }
        }
        failure {
            script {
                echo "❌ Deployment failed! Rolling back..."
                
                if (env.IS_MODEL_UPDATE == 'true') {
                    // Rollback model update
                    sh "kubectl rollout undo deployment/fer-service -n ${NAMESPACE}"
                    echo "Model rollback completed"
                } else {
                    // Rollback code update
                    sh "kubectl rollout undo deployment/fer-service -n ${NAMESPACE}"
                    echo "Code rollback completed"
                }
            }
        }
    }
}
