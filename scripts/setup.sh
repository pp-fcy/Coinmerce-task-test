#!/usr/bin/env bash
# scripts/setup.sh — Bootstrap the full local dev environment
# Usage: ./scripts/setup.sh [--with-istio] [--with-monitoring]

set -euo pipefail

WITH_ISTIO=false
WITH_MONITORING=false

for arg in "$@"; do
  case $arg in
    --with-istio)      WITH_ISTIO=true ;;
    --with-monitoring) WITH_MONITORING=true ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $1"; }

# ── Prerequisites check ───────────────────────────────────────────────────
log "Checking prerequisites..."
for cmd in docker kubectl kind helm; do
  if ! command -v $cmd &>/dev/null; then
    echo "Missing: $cmd — please install it first."
    exit 1
  fi
done

# ── kind cluster ──────────────────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "coinmerce"; then
  warn "Kind cluster 'coinmerce' already exists — skipping creation"
else
  log "Creating kind cluster..."
  kind create cluster --config kind-config.yaml
fi

kubectl config use-context kind-coinmerce

# ── Deploy application ────────────────────────────────────────────────────
log "Deploying application..."
kubectl apply -f k8s/webapp/namespace.yaml
kubectl apply -f k8s/webapp/deployment.yaml
kubectl apply -f k8s/webapp/service.yaml
kubectl apply -f k8s/webapp/policy.yaml

log "Waiting for rollout..."
kubectl rollout status deployment/coinmerce-app -n coinmerce --timeout=120s

# ── Monitoring (optional) ─────────────────────────────────────────────────
if [ "$WITH_MONITORING" = true ]; then
  log "Installing kube-prometheus-stack..."
  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo update
  helm upgrade --install kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    -f monitoring/kube-prometheus-stack-values.yaml \
    --wait --timeout=300s
  kubectl apply -f k8s/monitoring/grafana-dashboard-cm.yaml
  log "Grafana: kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring → http://localhost:3000 (admin/admin)"
fi

# ── Istio (optional) ──────────────────────────────────────────────────────
if [ "$WITH_ISTIO" = true ]; then
  log "Installing Istio..."
  if ! command -v istioctl &>/dev/null; then
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.21.0 sh -
    export PATH="$PATH:$PWD/istio-1.21.0/bin"
  fi
  istioctl install --set profile=minimal -y
  kubectl label namespace coinmerce istio-injection=enabled --overwrite
  kubectl rollout restart deployment/coinmerce-app -n coinmerce
  kubectl apply -f istio/manifests.yaml
fi

# ── Smoke test ────────────────────────────────────────────────────────────
log "Running smoke test..."
kubectl port-forward svc/coinmerce-app 8080:80 -n coinmerce &
PF_PID=$!
sleep 4

RESPONSE=$(curl -sf http://localhost:8080/ || echo "FAILED")
kill $PF_PID 2>/dev/null || true

if echo "$RESPONSE" | grep -q "Hello World"; then
  log "✓ Smoke test passed: $RESPONSE"
else
  echo "✗ Smoke test FAILED: $RESPONSE"
  exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  App:       kubectl port-forward svc/coinmerce-app 8080:80 -n coinmerce → http://localhost:8080"
echo "  Tests:     curl -sf http://localhost:8080/ | grep Hello"
[ "$WITH_MONITORING" = true ] && echo "  Grafana:   kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
echo ""
