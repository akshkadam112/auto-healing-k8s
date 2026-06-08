#!/usr/bin/env bash
# Simulate OOMKill — pod allocates more memory than its limit (150Mi).
# Healed by: kopf oomkill handler (raises memory limit by 50%, removes MEMORY_HOG_MB)
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}
DEPLOY=${DEPLOY:-sample-app}
HOG_MB=${HOG_MB:-200}   # must exceed the Helm chart limit of 150Mi

echo "[oomkill] Injecting MEMORY_HOG_MB=${HOG_MB} into deployment/${DEPLOY}"
kubectl set env deployment/"${DEPLOY}" MEMORY_HOG_MB="${HOG_MB}" -n "${NAMESPACE}"

echo "[oomkill] Waiting for pod to be OOMKilled (this may take 10-30s)..."
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=sample-app -w &
WATCH_PID=$!
sleep 45
kill "${WATCH_PID}" 2>/dev/null || true

echo "[oomkill] Fault injected. Watch the operator heal it:"
echo "  kubectl logs -n demo -l app=auto-healing-operator -f"
echo "  kubectl describe deployment/${DEPLOY} -n ${NAMESPACE}"
