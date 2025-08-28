# Facial Expression Recognition MLOps

A comprehensive Facial Emotion Recognition (FER) service built with FastAPI, PyTorch, and Kubernetes, featuring automated CI/CD pipeline for model updates.

## 🚀 Features

- **Facial Emotion Recognition**: 7 emotion classes using EfficientFace architecture
- **MLOps Pipeline**: Automated CI/CD for both code and model updates
- **Kubernetes Deployment**: Scalable containerized deployment
- **Monitoring**: Prometheus, Grafana, and Jaeger integration
- **Model Versioning**: Automatic model metadata tracking and deployment

## 🏗️ Architecture

```
Training → Model Update → CI/CD Trigger → Docker Build → K8s Deploy → Monitoring
```

## 📁 Project Structure

```
├── api/                    # FastAPI application
├── src/                    # Training scripts and models
├── model/                  # Model weights and metadata
├── k8s/                    # Kubernetes manifests
├── tests/                  # Test suite
├── scripts/                # Deployment scripts
├── Jenkinsfile            # CI/CD pipeline
└── requirements.txt        # Python dependencies
```

## 🔧 Setup

### Prerequisites

- Python 3.9+
- Docker
- Kubernetes cluster
- Jenkins server

### Installation

1. **Clone repository**
```bash
git clone https://github.com/undertanker86/Facial--Expression-Recognition-MLOps.git
cd Facial--Expression-Recognition-MLOps
```

2. **Install dependencies**
```bash
pip install -r requirements.txt
```

3. **Setup Kubernetes**
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/
```

4. **Setup Jenkins (Automated)**
```bash
# Make script executable
chmod +x scripts/setup-jenkins.sh

# Run setup (update JENKINS_URL, USER, PASS as needed)
export JENKINS_URL="http://your-jenkins-url:8080"
export JENKINS_USER="your-username"
export JENKINS_PASS="your-password"
./scripts/setup-jenkins.sh
```

5. **Test CI/CD Pipeline**
```bash
# Make script executable
chmod +x scripts/test-cicd.sh

# Run tests
./scripts/test-cicd.sh
```

### Manual Jenkins Setup

If automated setup fails, manually create Jenkins job:

1. **Create Pipeline Job**
   - Name: `fer-emotion-recognition`
   - Type: Pipeline
   - Repository: `https://github.com/undertanker86/Facial--Expression-Recognition-MLOps.git`
   - Script Path: `Jenkinsfile`

2. **Setup Credentials**
   - `dockerhub-credentials`: Docker Hub username/password
   - `github-credentials`: GitHub personal access token

3. **Setup Webhook**
   - URL: `http://jenkins-url/github-webhook/`
   - Events: Push events only

## 🚀 CI/CD Pipeline

### Code Updates
- Push to `main` branch triggers code deployment
- Builds new Docker image
- Deploys to Kubernetes
- Runs health checks

### Model Updates
- Train new model using `python src/train.py`
- Automatically triggers CI/CD via model tags
- Deploys new model without code changes
- Maintains model versioning

### Pipeline Stages
1. **Checkout**: Clone code and detect update type
2. **Build**: Create Docker image
3. **Test**: Run unit tests
4. **Push**: Upload to Docker Hub
5. **Deploy**: Update Kubernetes deployment
6. **Health Check**: Verify service health

## 📊 Model Training

### Training Script
```bash
python src/train.py
```

### Automatic CI/CD Trigger
After training, the script automatically:
- Updates model metadata
- Creates version tag
- Pushes to GitHub
- Triggers Jenkins pipeline

### Model Metadata
```json
{
  "model_path": "model/outputs/best_model.pth",
  "version": "1.0.1",
  "description": "Model trained with new data",
  "updated_at": "2024-01-16T15:30:00",
  "checksum": "abc123...",
  "training_data_version": "v1.0.0-2024-01-15"
}
```

## 🐳 Docker

### Build Image
```bash
docker build -t undertanker86/fer-service .
```

### Run Locally
```bash
docker run -p 8000:8000 undertanker86/fer-service
```

## ☸️ Kubernetes

### Deploy
```bash
kubectl apply -f k8s/
```

### Check Status
```bash
kubectl get pods -n fer-project
kubectl get svc -n fer-project
```

### Update Model
```bash
kubectl set image deployment/fer-service fer-service=undertanker86/fer-service:model-1.0.1 -n fer-project
```

## 📈 Monitoring

### Metrics
- Request rate and response time
- Model inference performance
- Error rates and success rates
- Resource utilization

### Dashboards
- Grafana dashboards for FER service
- Prometheus metrics collection
- Jaeger distributed tracing

## 🔄 Workflow Examples

### 1. Code Update
```bash
# Make code changes
git add .
git commit -m "Add new feature"
git push origin main
# Jenkins automatically deploys
```

### 2. Model Update
```bash
# Train new model
python src/train.py
# Automatically triggers CI/CD
# New model deployed to production
```

### 3. Manual Model Deploy
```bash
# Deploy specific model version
kubectl set image deployment/fer-service fer-service=undertanker86/fer-service:model-1.0.1 -n fer-project
```

## 🛠️ Development

### Local Development
```bash
# Run API locally
cd api
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Run tests
pytest tests/
```

### Adding New Models
1. Update training script
2. Add model architecture
3. Update requirements.txt
4. Test locally
5. Commit and push

## 📝 Configuration

### Environment Variables
- `PYTHONPATH`: Application path
- `KUBECONFIG`: Kubernetes config path
- `DOCKER_IMAGE`: Docker image name

### Jenkins Configuration
- `dockerhub-credentials`: Docker Hub access
- `kubeconfig`: Kubernetes context
- Webhook from GitHub

## 🚨 Troubleshooting

### Common Issues
1. **Model not updating**: Check metadata file and git tags
2. **Deployment failed**: Check Kubernetes logs and rollback
3. **CI/CD not triggering**: Verify webhook and Jenkins configuration

### Debug Commands
```bash
# Check model metadata
cat model/model_metadata.json

# Check Kubernetes status
kubectl get pods -n fer-project
kubectl logs -n fer-project -l app=fer-service

# Check Jenkins pipeline
# View Jenkins job logs
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Add tests
5. Submit pull request

## 📄 License

This project is licensed under the MIT License.

## 🙏 Acknowledgments

- EfficientFace architecture
- FER+ dataset
- FastAPI framework
- Kubernetes community
# Test CI/CD Pipeline - Thu Aug 28 01:43:31 PM +07 2025
