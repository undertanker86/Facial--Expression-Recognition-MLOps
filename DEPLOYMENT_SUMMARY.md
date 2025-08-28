## FER Project – Deployment, Monitoring, and Tracing Summary

This document captures the current, working setup of the FER service on Kubernetes (Minikube), including networking (NGINX Ingress), metrics (Prometheus + Grafana), and tracing (OpenTelemetry → Jaeger).

### What is deployed
- Application: FastAPI FER service (`fer-service`)
  - Image: `undertanker86/fer-service:latest`
  - Entrypoint: `api.main:app` (instrumented with Prometheus metrics + OpenTelemetry tracing)
  - Port: 8000/TCP
- Kubernetes resources (`k8s/`)
  - `namespace.yaml`, `configmap.yaml`, `deployment.yaml`, `service.yaml`, `ingress.yaml`
  - Monitoring stack in `k8s/monitoring/`: Prometheus, Grafana, Jaeger, kube-state-metrics, node-exporter
  - `k8s/monitoring-ingress.yaml` for monitoring UIs via NGINX
- NGINX Ingress Controller (Minikube addon)

---

## Networking & Access
- Hosts mapping (port-forward mode):
  ```bash
  echo "127.0.0.1 fer.local grafana.fer.local prometheus.fer.local jaeger.fer.local" | sudo tee -a /etc/hosts
  ```
- Start Ingress port-forward:
  ```bash
  kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80
  ```
- Access:
  - App: `http://fer.local/` via NGINX (through 127.0.0.1:8080)
  - Grafana: `http://grafana.fer.local/`
  - Prometheus: `http://prometheus.fer.local/`
  - Jaeger UI: `http://jaeger.fer.local/`

---

## Application (FastAPI)
- File: `api/main.py`
  - Prometheus metrics exposed at `GET /metrics` (prometheus_client).
  - Requests counters, latency histograms, prediction counters, model parameters, active requests, etc.
  - OpenTelemetry tracing with resource:
    - `service.name=fer-service`, `service.version`, `deployment.environment`.
  - Tracing exporter: OTLP HTTP → Jaeger Collector.
    - Endpoint comes from ConfigMap env: `OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318/v1/traces`.
  - FastAPI auto-instrumentation enabled (`FastAPIInstrumentor.instrument_app`).

Endpoints
- `GET /` root
- `GET /health` health info
- `GET /metrics` Prometheus exposition
- `POST /predict` image upload (multipart) → emotion + confidence (CPU inference)

---

## Configuration
- ConfigMap `k8s/configmap.yaml` (key values)
  - `OTEL_SERVICE_NAME=fer-service`
  - `OTEL_SERVICE_VERSION=1.0.0`
  - `OTEL_DEPLOYMENT_ENVIRONMENT=production`
  - `OTEL_TRACES_SAMPLER=always_on`
  - `OTEL_METRICS_EXPORTER=console` (for OTel metrics SDK; Prometheus metrics are via /metrics)
  - `OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318/v1/traces`
  - `MODEL_PATH=/app/model/best_model_now.pth`

- Deployment `k8s/deployment.yaml`
  - `replicas: 2`
  - `image: undertanker86/fer-service:latest`
  - Env injected from `fer-config`
  - Probes: `/health`

---

## Monitoring (Prometheus + Grafana)
- Prometheus configuration `k8s/monitoring/prometheus-config.yaml` includes jobs:
  - `fer-service` → `fer-service:8000/metrics`
  - `jaeger` → `jaeger:14269/metrics` (Jaeger internal metrics)
  - `node-exporter`, `kube-state-metrics`, `nginx-ingress`, plus pod discovery
- Grafana provisioning `k8s/monitoring/grafana-dashboards.yaml`
  - FER Service Dashboard: request rate, p95 latency, error rate, memory, prediction counts, active requests, model parameters, confidence stats
  - Kubernetes Cluster Overview: pod status, CPU, memory, container memory, service health

Notes
- Grafana panels read METRICS from Prometheus (not Jaeger). Jaeger is only for TRACES.

---

## Tracing (Jaeger)
- Manifests: `k8s/monitoring/jaeger.yaml`
  - Jaeger all-in-one: UI (16686), Collector (14268 HTTP), OTLP HTTP (4318), OTLP gRPC (4317), metrics (14269), Agent (6831/UDP)
  - Service exposes 16686/14268/4318/14269/6831.
- OpenTelemetry in app exports spans via OTLP HTTP to `http://jaeger:4318/v1/traces`.
- Jaeger UI service list will include `fer-service` once spans are ingested.

Verification
- Generate traffic (through ingress):
  ```bash
  for i in {1..10}; do curl -s -H 'Host: fer.local' http://127.0.0.1:8080/health >/dev/null; done
  ```
- Prometheus queries (examples):
  - `rate(fer_api_requests_total[5m])`
  - `histogram_quantile(0.95, rate(fer_api_request_duration_seconds_bucket[5m]))`
  - `fer_model_parameters_total`
  - Jaeger intake sanity: `rate(jaeger_collector_spans_received_total[5m])` (> 0 when traces arrive)
- Jaeger UI: choose service `fer-service` → Find Traces.

---

## Build & Deploy
- Build and push image:
  ```bash
  docker build -t undertanker86/fer-service:latest .
  docker push undertanker86/fer-service:latest
  ```
- Apply configuration and rollout:
  ```bash
  kubectl apply -f k8s/configmap.yaml -n fer-project
  kubectl rollout restart deploy/fer-service -n fer-project
  kubectl rollout status deploy/fer-service -n fer-project
  ```

---

## Troubleshooting Cheatsheet
- Ingress access: ensure port-forward (or use `minikube tunnel` for LoadBalancer).
- Missing metrics in Grafana: confirm Prometheus target `fer-service` is UP; check `/metrics`.
- Jaeger shows only `jaeger-all-in-one`:
  - Ensure `OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318/v1/traces`.
  - Confirm Service `jaeger` exposes port 4318/TCP.
  - Generate traffic; check Prometheus: `rate(jaeger_collector_spans_received_total[5m])`.
- Pod restarts: `kubectl -n fer-project logs deploy/fer-service`.

---

## Housekeeping
- Temporary local test scripts were removed to keep the repo clean (`build-simple.sh`, `test-simple.sh`, `test-metrics.sh`, `test-predict.sh`).


