# Auto-Healing Kubernetes Cluster

A production-grade demo showing how a Kubernetes cluster can detect and recover from 12 real-world failure scenarios automatically — with measurable MTTR.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        minikube cluster                         │
│                                                                 │
│  ┌──────────────┐   fails    ┌─────────────────────────────┐   │
│  │  sample-app  │──────────▶ │     Prometheus + Alertmanager│   │
│  │  (Python/    │            │     (kube-prometheus-stack)  │   │
│  │   Flask)     │◀── heals ──│              │               │   │
│  └──────────────┘            └──────────────┼───────────────┘   │
│                                             │ webhook           │
│  ┌──────────────────────────────────────────▼───────────────┐   │
│  │               kopf Operator (Python)                      │   │
│  │   crashloop.py │  oomkill.py  │  rollout.py               │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Native healers:  Karpenter │ cert-manager │ node-problem-detector │ HPA
└─────────────────────────────────────────────────────────────────┘
```

---

## Failure Coverage

### Pod-level (4)

| Failure | How it's simulated | Healed by | Script |
|---|---|---|---|
| CrashLoopBackOff | `CRASH_ON_START=true` env var | **kopf** `crashloop.py` | `simulate-crashloop.sh` |
| OOMKilled | `MEMORY_HOG_MB=200` exceeds 150Mi limit | **kopf** `oomkill.py` | `simulate-oomkill.sh` |
| Liveness probe fail | `LIVENESS_FAIL=true` → `/health` returns 500 | K8s native (kubelet restart) | `simulate-liveness-fail.sh` |
| Readiness probe fail | `READINESS_FAIL=true` → `/ready` returns 503 | K8s native (removed from endpoints) | `simulate-readiness-fail.sh` |

### Node-level (4)

| Failure | How it's simulated | Healed by | Script |
|---|---|---|---|
| Node NotReady | Stop kubelet via minikube SSH | Karpenter (drain + replace node) | `simulate-node-notready.sh` |
| Disk pressure | `dd` to fill node disk | Karpenter eviction manager | `simulate-disk-pressure.sh` |
| CPU / memory pressure | `stress-ng` on node | Karpenter eviction thresholds | `simulate-cpu-pressure.sh` |
| Kernel / OS fault | Inject `KernelDeadlock` taint | node-problem-detector → reschedule | `simulate-kernel-fault.sh` |

### Workload & scaling (4)

| Failure | How it's simulated | Healed by | Script |
|---|---|---|---|
| Traffic spike / high latency | `hey` load generator | HPA scales pods out | `simulate-traffic-spike.sh` |
| Pending pods | Pod requesting 32 CPU / 64Gi | Karpenter provisions new node | `simulate-pending-pods.sh` |
| Deployment stuck / rollout hung | `SLOW_START_SECONDS=120` vs 90s deadline | **kopf** `rollout.py` (rollback) | `simulate-stuck-rollout.sh` |
| TLS cert expiry | cert-manager Certificate with 2m duration | cert-manager auto-renew | `simulate-tls-expiry.sh` |

---

## Stack

| Component | Role |
|---|---|
| **minikube** | Local Kubernetes cluster |
| **Python + Flask** | Sample app with env-var failure injection |
| **kopf** | Custom operator — CrashLoop, OOMKill, stuck rollout |
| **kube-prometheus-stack** | Prometheus, Alertmanager, Grafana |
| **Karpenter** | Node lifecycle — NotReady, disk/CPU pressure, pending pods |
| **cert-manager** | TLS certificate auto-renewal |
| **node-problem-detector** | Kernel / OS fault detection |
| **HPA** | Horizontal pod autoscaling on traffic spikes |
| **Helm** | Package management for sample-app and Prometheus |

---

## Project Structure

```
auto-healing-k8s/
├── app/
│   ├── app.py                  Flask app with all failure injection points
│   ├── requirements.txt
│   └── Dockerfile
├── helm/
│   ├── sample-app/             Helm chart (Deployment, Service, HPA)
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── prometheus/
│       └── values.yaml         kube-prometheus-stack config + Alertmanager routes
├── operator/
│   ├── main.py                 kopf operator entry point
│   ├── Dockerfile
│   ├── requirements.txt
│   └── handlers/
│       ├── crashloop.py        CrashLoopBackOff → remove bad env var, clean rollout
│       ├── oomkill.py          OOMKilled → raise memory limit 50%, restart
│       └── rollout.py          Stuck rollout → roll back to previous ReplicaSet
├── alerts/
│   └── rules.yaml              PrometheusRule for all 12 failure scenarios
├── manifests/
│   ├── namespace.yaml
│   └── operator/
│       ├── deployment.yaml
│       ├── rbac.yaml           ClusterRole + ServiceAccount for kopf
│       └── configmap.yaml      Operator tuning (thresholds, annotation key)
└── scripts/
    ├── simulate-crashloop.sh
    ├── simulate-oomkill.sh
    ├── simulate-stuck-rollout.sh
    ├── simulate-liveness-fail.sh
    ├── simulate-readiness-fail.sh
    ├── simulate-node-notready.sh
    ├── simulate-disk-pressure.sh
    ├── simulate-cpu-pressure.sh
    ├── simulate-kernel-fault.sh
    ├── simulate-traffic-spike.sh
    ├── simulate-pending-pods.sh
    ├── simulate-tls-expiry.sh
    └── measure-mttr.sh         Times recovery end-to-end for any scenario
```

---

## Quick Start

### 1. Start minikube

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
minikube addons enable metrics-server
```

### 2. Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f helm/prometheus/values.yaml
```

### 3. Build and load the sample-app image

```bash
eval $(minikube docker-env)
docker build -t sample-app:latest ./app
```

### 4. Deploy the sample-app

```bash
kubectl apply -f manifests/namespace.yaml

helm upgrade --install sample-app ./helm/sample-app \
  -n demo --create-namespace
```

### 5. Build and deploy the kopf operator

```bash
eval $(minikube docker-env)
docker build -t auto-healing-operator:latest ./operator

kubectl apply -f manifests/operator/rbac.yaml
kubectl apply -f manifests/operator/configmap.yaml
kubectl apply -f manifests/operator/deployment.yaml
```

### 6. Apply alert rules

```bash
kubectl apply -f alerts/rules.yaml
```

---

## Running a Failure Scenario

Every script injects the fault and prints what to watch. Example end-to-end for CrashLoopBackOff:

```bash
# Terminal 1 — watch pods
kubectl get pods -n demo -w

# Terminal 2 — watch operator logs
kubectl logs -n demo -l app=auto-healing-operator -f

# Terminal 3 — inject the fault and measure MTTR
./scripts/measure-mttr.sh crashloop
```

Expected output:

```
✓ RECOVERED
─────────────────────────────────
Scenario:                 crashloop
Fault injected:           2024-01-15 10:23:01
Recovered at:             2024-01-15 10:23:47
MTTR:                     46s
─────────────────────────────────
```

---

## App Failure Injection Reference

All failures are injected via `kubectl set env` — no image rebuild required.

| Env var | Value | Effect |
|---|---|---|
| `CRASH_ON_START` | `true` | `sys.exit(1)` at startup → CrashLoopBackOff |
| `MEMORY_HOG_MB` | `200` | Allocates 200 MB → OOMKill (limit: 150Mi) |
| `SLOW_START_SECONDS` | `120` | Sleeps 120s → rollout stuck (deadline: 90s) |
| `LIVENESS_FAIL` | `true` | `/health` returns 500 → kubelet restarts pod |
| `READINESS_FAIL` | `true` | `/ready` returns 503 → removed from endpoints |
| `CPU_STRESS_CORES` | `4` | Busy threads → CPU saturation |
| `RESPONSE_DELAY` | `5` | Sleeps 5s per request → high latency |

Reset any fault:

```bash
kubectl set env deployment/sample-app ENV_VAR_NAME=false -n demo
```

---

## How the kopf Operator Works

### CrashLoopBackOff (`handlers/crashloop.py`)

1. Watches `pods.status.containerStatuses` for `reason=CrashLoopBackOff`
2. Triggers after `restartCount >= 3`
3. Walks ownerReferences (Pod → ReplicaSet → Deployment) to find the parent
4. Removes `CRASH_ON_START` from the Deployment env vars → triggers a clean rollout
5. Falls back to deleting the pod if no parent Deployment is found

### OOMKilled (`handlers/oomkill.py`)

1. Watches `pods.status.containerStatuses` for `lastState.terminated.reason=OOMKilled`
2. Raises the container's memory limit by 50% on the parent Deployment
3. Also removes the `MEMORY_HOG_MB` env var if it was an injected fault
4. Patches the Deployment → rolling restart with higher limit

### Stuck Rollout (`handlers/rollout.py`)

1. Watches `deployments.status.conditions` for `type=Progressing, status=False, reason=ProgressDeadlineExceeded`
2. Lists all ReplicaSets owned by the Deployment, sorts by creation time
3. Patches the Deployment spec with the previous ReplicaSet's pod template → effective rollback
4. Annotates the Deployment with rollback metadata for auditability

---

## Measuring MTTR

```bash
# Measure recovery time for any scenario
./scripts/measure-mttr.sh <scenario>

# Scenarios: crashloop | oomkill | stuck-rollout | liveness | readiness
```

The script records the exact timestamp of fault injection, polls until `readyReplicas == desiredReplicas`, and prints the delta in seconds.
