#!/usr/bin/env bash
# scripts/install-argocd.sh — Install Argo CD on local kind cluster and apply the coinmerce Application.
set -euo pipefail
 
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[argocd]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $1"; }
 
ARGOCD_VERSION="v2.10.0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
 
log "Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
 
log "Waiting for ArgoCD to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
 
log "Patching argocd-server to insecure mode (no TLS for local dev)..."
kubectl patch deployment argocd-server -n argocd \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
 
log "Waiting for rollout after patch..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=120s
 
PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d)
 
log "Applying Application coinmerce (multi-source, sync waves)..."
kubectl apply -f "$ROOT/argocd/application.yaml"
 

echo "  Port forward: kubectl port-forward svc/argocd-server 8090:80 -n argocd"
echo "  URL:          http://localhost:8090"
echo "  Username:     admin"
echo "  Password:     ${PASS}"
