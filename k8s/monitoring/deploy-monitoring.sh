#!/bin/bash

echo "🚀 Deploying enhanced monitoring stack for FER Project..."

# Apply ConfigMap updates
echo "📝 Applying ConfigMap updates..."
kubectl apply -f ../configmap.yaml

# Apply Prometheus config updates
echo "📊 Applying Prometheus configuration updates..."
kubectl apply -f prometheus-config.yaml

# Apply Grafana dashboard updates
echo "📈 Applying Grafana dashboard updates..."
kubectl apply -f grafana-dashboards.yaml

# Restart Prometheus to pick up new config
echo "🔄 Restarting Prometheus..."
kubectl rollout restart deploy/prometheus -n fer-project

# Restart Grafana to pick up new dashboards
echo "🔄 Restarting Grafana..."
kubectl rollout restart deploy/grafana -n fer-project

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n fer-project
kubectl wait --for=condition=available --timeout=300s deployment/grafana -n fer-project

# Apply deployment updates
echo "🚀 Applying FER service deployment updates..."
kubectl apply -f ../deployment.yaml

# Restart FER service to pick up new config
echo "🔄 Restarting FER service..."
kubectl rollout restart deploy/fer-service -n fer-project

# Wait for FER service to be ready
echo "⏳ Waiting for FER service to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/fer-service -n fer-project

echo "✅ Enhanced monitoring stack deployed successfully!"
echo ""
echo "📊 Monitoring endpoints:"
echo "  - Prometheus: http://prometheus.fer.local"
echo "  - Grafana: http://grafana.fer.local (admin/admin)"
echo "  - Jaeger: http://jaeger.fer.local"
echo "  - AlertManager: http://alertmanager.fer.local"
echo ""
echo "🔍 Check service status:"
echo "  kubectl get pods -n fer-project"
echo "  kubectl get svc -n fer-project"
echo ""
echo "📈 Check Prometheus targets:"
echo "  kubectl port-forward svc/prometheus 9090:9090 -n fer-project"
echo "  # Then visit http://localhost:9090/targets"

