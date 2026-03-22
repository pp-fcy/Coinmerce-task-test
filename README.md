# Coinmerce DevOps Challenge

A production-grade local Kubernetes deployment of a webapp using `crccheck/hello-world` demonstrating
real-world DevOps practices: kind cluster, security hardening,
Prometheus/Grafana monitoring, Istio service mesh, and **pre-commit** (kubeconform,
Gitleaks). **GitHub Actions** runs only `pre-commit run --all-files`.

---

## Architecture

```
GitHub Actions (CI)
  └── pre-commit run --all-files — same hooks as locally (.pre-commit-config.yaml)

Local checks (pre-commit + optional CLI)
  ├── kubeconform — validate Kubernetes YAML (k8s/, istio/, argocd/)
  ├── Gitleaks    — scan repo for leaked secrets

Kubernetes (kind — 1 control-plane + 2 workers)
  ├── Namespace: coinmerce (Istio injection enabled)
  ├── Deployment: crccheck/hello-world:v1.0.0 (2 replicas, port 8000)
  ├── HPA (min 2, max 10 replicas, CPU 60%)
  ├── PodDisruptionBudget (minAvailable: 1)
  └── NetworkPolicy (default deny, allow only port 8000)

Monitoring (optional)
  ├── Prometheus (kube-prometheus-stack)
  └── Grafana    (single Webapp dashboard — kube-state + cAdvisor: replicas, pods, CPU/memory)

Service Mesh (Istio)
  ├── Gateway + VirtualService (retries, 10s timeout)
  └── DestinationRule (circuit breaker — eject after 3x 5xx)

GitOps (ArgoCD)
  └── One Application `coinmerce` — multi-source, sync waves: web/networking.istio.io-CRDs (0) → istio (1) → stack (2) → extras (3)
```

**Layout:** `k8s/webapp/` is the Hello World workload. `k8s/monitoring/` holds the Grafana dashboard ConfigMap. `istio/` holds optional mesh CRDs. `argocd/application.yaml` is the single **Application** (multi-source: webapp, istio, Helm chart, monitoring extras).

---

## Quick Start

### Prerequisites

```bash
brew install docker kubectl kind helm
```

### One-command setup

```bash
# Basic
./scripts/setup.sh

# With Prometheus + Grafana
./scripts/setup.sh --with-monitoring

# Full stack (+ Istio)
./scripts/setup.sh --with-monitoring --with-istio
```

### Manual

```bash
kind create cluster --config kind-config.yaml
kubectl apply -f k8s/webapp/namespace.yaml
kubectl apply -f k8s/webapp/deployment.yaml
kubectl apply -f k8s/webapp/service.yaml
kubectl apply -f k8s/webapp/policy.yaml
kubectl rollout status deployment/coinmerce-app -n coinmerce --timeout=120s
kubectl port-forward svc/coinmerce-app 8080:80 -n coinmerce &
curl -sf http://localhost:8080/ | grep -q "Hello World" && echo OK || echo FAIL
```

---

## Pre-commit (local hooks)

```bash
pip install pre-commit   # or: brew install pre-commit
pre-commit install
pre-commit run --all-files
```

Configuration is in `.pre-commit-config.yaml`.

### CI (GitHub Actions)

On every push / pull request to `main` or `master`, [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml) uses [`pre-commit/action`] to run **`pre-commit run --all-files`**

---

## Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout=300s
kubectl apply -f k8s/monitoring/grafana-dashboard-cm.yaml
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring    # http://localhost:3000 (admin/admin)
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

Grafana loads one dashboard (**Coinmerce Webapp**): deployment replicas, running pods, CPU and memory per pod (from **kube-state-metrics** and **cAdvisor**).

---

## Service Mesh (Istio)

```bash
istioctl install --set profile=minimal -y
kubectl label namespace coinmerce istio-injection=enabled --overwrite
kubectl rollout restart deployment/coinmerce-app -n coinmerce
kubectl apply -f istio/manifests.yaml
```

Adds: retry logic (3 attempts on 5xx), 10s timeout, circuit breaker (ejects pod after 3 consecutive errors for 30s).

---

## GitOps (ArgoCD)

**Single Application `coinmerce`** (`argocd/application.yaml`) uses **multi-source** and **resource sync waves** (no nested Application CRs):

| Sync wave | Source | What deploys |
|-----------|--------|----------------|
| `0` | Helm `istio/base` | Istio CRDs (including `networking.istio.io` / `VirtualService`) |
| `0` | `k8s/webapp` | Namespace, Deployment, Service, HPA, PDB, NetworkPolicy |
| `1` | `istio` | Gateway, VirtualService, DestinationRule |
| `2` | Helm `kube-prometheus-stack` | Prometheus / Grafana / operator (values in `monitoring/`) |
| `3` | `k8s/monitoring` | Grafana dashboard ConfigMap |

Add the repo in `ArgoCD` GUI.

Then install the control plane and apply the `coinmerce` Application:

```bash
./scripts/install-argocd.sh   # also runs: kubectl apply -f argocd/application.yaml
# If Argo CD is already installed:
kubectl apply -f argocd/application.yaml

kubectl port-forward svc/argocd-server 8090:80 -n argocd    # http://localhost:8090
```

## Item can be improved

### Reliability & GitOps
1 A repo can be set for ArgoCD, and use `vault/other Secrets` manager  to store secrets
2 CICD can be set for iamge build.
3 Notification and alert can be added for the monitor system.
4 The docker image does not expose metrics, it should expose related metrics for real production.

### Security
1 Image pinning by digest (image@sha256:...) for reproducibility and to satisfy stricter policies.
2 NetworkPolicy / Istio: Revisit egress rules if you add real backends or DNS needs beyond the current allow list.
3 RBAC: Optional dedicated ServiceAccounts for workloads and tighter project than default.

### CI/CD
1 Smoke test can be added into the CICD pipeline.
2 For large project condtion and cache can be added.
