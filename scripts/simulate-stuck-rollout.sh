#!/usr/bin/env bash
# Simulate a stuck rollout — pod sleeps 120s before starting; readiness probe fails
# until the 90s progressDeadlineSeconds is breached.
# Healed by: kopf rollout handler (rolls back to previous stable revision)
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}
DEPLOY=${DEPLOY:-sample-app}
DELAY=${DELAY:-120}

echo "[stuck-rollout] Injecting SLOW_START_SECONDS=${DELAY} into deployment/${DEPLOY}"
kubectl set env deployment/"${DEPLOY}" SLOW_START_SECONDS="${DELAY}" -n "${NAMESPACE}"

echo "[stuck-rollout] Rollout will become stuck after ${DELAY}s startup delay vs 90s deadline..."
kubectl rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}" --timeout=120s || true

echo "[stuck-rollout] Fault injected. Watch the operator roll back:"
echo "  kubectl logs -n demo -l app=auto-healing-operator -f"
echo "  kubectl rollout history deployment/${DEPLOY} -n ${NAMESPACE}"
