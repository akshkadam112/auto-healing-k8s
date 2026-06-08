#!/usr/bin/env bash
# Simulate liveness probe failure — /health returns 500.
# Healed by: K8s native (kubelet restarts the container after failureThreshold=3)
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}
DEPLOY=${DEPLOY:-sample-app}

echo "[liveness] Injecting LIVENESS_FAIL=true into deployment/${DEPLOY}"
kubectl set env deployment/"${DEPLOY}" LIVENESS_FAIL=true -n "${NAMESPACE}"

echo "[liveness] Pods will restart after 3 consecutive liveness probe failures (~30s)."
echo "  Watch: kubectl get pods -n ${NAMESPACE} -w"
echo ""
echo "[liveness] To recover manually (K8s heals automatically):"
echo "  kubectl set env deployment/${DEPLOY} LIVENESS_FAIL=false -n ${NAMESPACE}"
