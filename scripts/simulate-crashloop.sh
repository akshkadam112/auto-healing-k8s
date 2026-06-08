#!/usr/bin/env bash
# Simulate CrashLoopBackOff — pod exits immediately on startup.
# Healed by: kopf crashloop handler (removes CRASH_ON_START, triggers clean rollout)
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}
DEPLOY=${DEPLOY:-sample-app}

echo "[crashloop] Injecting CRASH_ON_START=true into deployment/${DEPLOY}"
kubectl set env deployment/"${DEPLOY}" CRASH_ON_START=true -n "${NAMESPACE}"

echo "[crashloop] Waiting for pods to enter CrashLoopBackOff..."
kubectl rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}" --timeout=30s || true
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=sample-app

echo "[crashloop] Fault injected. Watch the operator heal it:"
echo "  kubectl logs -n demo -l app=auto-healing-operator -f"
echo "  kubectl get pods -n ${NAMESPACE} -w"
