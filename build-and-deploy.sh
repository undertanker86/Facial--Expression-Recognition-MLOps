#!/bin/bash

echo "🚀 Building and deploying enhanced FER service..."

# Build new Docker image
echo "🔨 Building Docker image..."
docker build -t undertanker86/fer-service:latest .

# Push to Docker Hub
echo "📤 Pushing to Docker Hub..."
docker push undertanker86/fer-service:latest

# Deploy enhanced monitoring
echo "📊 Deploying enhanced monitoring..."
cd k8s/monitoring
./deploy-monitoring.sh

# Wait for deployment to complete
echo "⏳ Waiting for deployment to complete..."
sleep 30

# Test the new metrics
echo "🧪 Testing new metrics..."
cd ../..
./test-metrics.sh

echo ""
echo "✅ Enhanced FER service deployed successfully!"
echo ""
echo "🔍 Check the following:"
echo "1. Grafana dashboards should now show data for all panels"
echo "2. Jaeger should show 'fer-service' in the service list"
echo "3. Prometheus should have Jaeger metrics"
echo "4. All FER service metrics should be populated"
echo ""
echo "📊 Access URLs:"
echo "  - Grafana: http://grafana.fer.local (admin/admin)"
echo "  - Jaeger: http://jaeger.fer.local"
echo "  - Prometheus: http://prometheus.fer.local"
