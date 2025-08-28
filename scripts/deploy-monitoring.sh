#!/bin/bash

# Deploy Monitoring Stack for FER Project
# This script deploys Prometheus, Grafana, and Jaeger

set -e

echo "📊 Deploying Monitoring Stack for FER Project..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="fer-project"
PROMETHEUS_STORAGE="5Gi"
GRAFANA_STORAGE="2Gi"
GRAFANA_PASSWORD="admin123"

# Check if kubectl is available
check_kubectl() {
    echo "🔍 Checking kubectl..."
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl is required but not installed${NC}"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        echo "Please check:"
        echo "1. Kubernetes cluster is running"
        echo "2. kubectl context is set correctly"
        echo "3. You have access to the cluster"
        exit 1
    fi
    
    echo -e "${GREEN}✅ kubectl check passed${NC}"
}

# Create namespace
create_namespace() {
    echo "📁 Creating namespace: $NAMESPACE"
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        echo -e "${YELLOW}⚠️ Namespace $NAMESPACE already exists${NC}"
    else
        kubectl create namespace $NAMESPACE
        echo -e "${GREEN}✅ Namespace $NAMESPACE created${NC}"
    fi
}

# Deploy Prometheus
deploy_prometheus() {
    echo "📈 Deploying Prometheus..."
    
    cat > /tmp/prometheus-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: $NAMESPACE
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    rule_files:
      - "prometheus_rules.yml"
    
    scrape_configs:
      - job_name: 'fer-service'
        static_configs:
          - targets: ['fer-service:8000']
        metrics_path: '/metrics'
        scrape_interval: 10s
      
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: \$1:\$2
            target_label: __address__
EOF

    cat > /tmp/prometheus-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: storage
          mountPath: /prometheus
        command:
        - /bin/prometheus
        - --config.file=/etc/prometheus/prometheus.yml
        - --storage.tsdb.path=/prometheus
        - --web.console.libraries=/etc/prometheus/console_libraries
        - --web.console.templates=/etc/prometheus/consoles
        - --storage.tsdb.retention.time=200h
        - --web.enable-lifecycle
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: storage
        persistentVolumeClaim:
          claimName: prometheus-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: $NAMESPACE
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
  type: ClusterIP
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PROMETHEUS_STORAGE
EOF

    kubectl apply -f /tmp/prometheus-config.yaml
    kubectl apply -f /tmp/prometheus-deployment.yaml
    
    echo -e "${GREEN}✅ Prometheus deployed successfully${NC}"
    
    # Cleanup
    rm -f /tmp/prometheus-config.yaml /tmp/prometheus-deployment.yaml
}

# Deploy Grafana
deploy_grafana() {
    echo "📊 Deploying Grafana..."
    
    cat > /tmp/grafana-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "$GRAFANA_PASSWORD"
        - name: GF_SECURITY_ADMIN_USER
          value: "admin"
        volumeMounts:
        - name: storage
          mountPath: /var/lib/grafana
        - name: dashboards
          mountPath: /etc/grafana/provisioning/dashboards
        - name: datasources
          mountPath: /etc/grafana/provisioning/datasources
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: grafana-pvc
      - name: dashboards
        configMap:
          name: grafana-dashboards
      - name: datasources
        configMap:
          name: grafana-datasources
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: $NAMESPACE
spec:
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
  type: ClusterIP
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $GRAFANA_STORAGE
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: $NAMESPACE
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus:9090
      access: proxy
      isDefault: true
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: $NAMESPACE
data:
  fer-dashboard.json: |
    {
      "dashboard": {
        "id": null,
        "title": "FER Service Dashboard",
        "tags": ["fer", "service"],
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(fer_api_requests_total[5m])",
                "legendFormat": "{{method}} {{endpoint}} - {{status}}"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "Response Time (95th percentile)",
            "type": "graph",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, rate(fer_api_request_duration_seconds_bucket[5m]))",
                "legendFormat": "95th percentile"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
          }
        ],
        "time": {"from": "now-1h", "to": "now"},
        "refresh": "5s"
      }
    }
EOF

    kubectl apply -f /tmp/grafana-deployment.yaml
    
    echo -e "${GREEN}✅ Grafana deployed successfully${NC}"
    echo -e "${YELLOW}📊 Grafana credentials: admin / $GRAFANA_PASSWORD${NC}"
    
    # Cleanup
    rm -f /tmp/grafana-deployment.yaml
}

# Deploy Jaeger
deploy_jaeger() {
    echo "🔍 Deploying Jaeger..."
    
    cat > /tmp/jaeger-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:latest
        ports:
        - containerPort: 16686
        - containerPort: 14268
        env:
        - name: COLLECTOR_OTLP_ENABLED
          value: "true"
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: $NAMESPACE
spec:
  selector:
    app: jaeger
  ports:
  - name: ui
    port: 16686
    targetPort: 16686
  - name: collector
    port: 14268
    targetPort: 14268
  type: ClusterIP
EOF

    kubectl apply -f /tmp/jaeger-deployment.yaml
    
    echo -e "${GREEN}✅ Jaeger deployed successfully${NC}"
    
    # Cleanup
    rm -f /tmp/jaeger-deployment.yaml
}

# Create ingress for monitoring
create_monitoring_ingress() {
    echo "🌐 Creating monitoring ingress..."
    
    cat > /tmp/monitoring-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring-ingress
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: prometheus.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 9090
  - host: grafana.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
  - host: jaeger.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jaeger
            port:
              number: 16686
EOF

    kubectl apply -f /tmp/monitoring-ingress.yaml
    
    echo -e "${GREEN}✅ Monitoring ingress created${NC}"
    
    # Cleanup
    rm -f /tmp/monitoring-ingress.yaml
}

# Show monitoring URLs
show_monitoring_urls() {
    echo ""
    echo -e "${BLUE}📊 Monitoring URLs:${NC}"
    echo "• Prometheus: http://prometheus.local (or port-forward to 9090)"
    echo "• Grafana: http://grafana.local (or port-forward to 3000)"
    echo "• Jaeger: http://jaeger.local (or port-forward to 16686)"
    echo ""
    echo -e "${BLUE}🔧 Port-forward commands:${NC}"
    echo "kubectl port-forward -n $NAMESPACE svc/prometheus 9090:9090"
    echo "kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000"
    echo "kubectl port-forward -n $NAMESPACE svc/jaeger 16686:16686"
    echo ""
    echo -e "${BLUE}📝 Credentials:${NC}"
    echo "• Grafana: admin / $GRAFANA_PASSWORD"
    echo "• Prometheus: no authentication required"
    echo "• Jaeger: no authentication required"
}

# Check deployment status
check_status() {
    echo ""
    echo -e "${BLUE}🔍 Checking deployment status...${NC}"
    
    echo "=== Namespace ==="
    kubectl get namespace $NAMESPACE
    
    echo ""
    echo "=== Deployments ==="
    kubectl get deployments -n $NAMESPACE
    
    echo ""
    echo "=== Services ==="
    kubectl get services -n $NAMESPACE
    
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n $NAMESPACE
    
    echo ""
    echo "=== PVCs ==="
    kubectl get pvc -n $NAMESPACE
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  FER Project Monitoring Setup${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    check_kubectl
    create_namespace
    deploy_prometheus
    deploy_grafana
    deploy_jaeger
    create_monitoring_ingress
    check_status
    show_monitoring_urls
    
    echo ""
    echo -e "${GREEN}🎉 Monitoring stack deployed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}⚠️ Note: You may need to add hosts to /etc/hosts or use port-forwarding${NC}"
}

# Run main function
main "$@"
