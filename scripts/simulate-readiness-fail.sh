#!/usr/bin/env bash
# Simulate readiness probe failure — /ready returns 503.
# Healed by: K8s native (pod removed from Service endpoints; traffic stops reaching it)
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}
DEPLOY=${DEPLOY:-sample-app}

echo "[readiness] Injecting READINESS_FAIL=true into deployment/${DEPLOY}"
kubectl set env deployment/"${DEPLOY}" READINESS_FAIL=true -n "${NAMESPACE}"

echo "[readiness] Pod will be removed from Service endpoints within ~15s."
echo "  Watch endpoints: kubectl get endpoints ${DEPLOY} -n ${NAMESPACE} -w"
echo ""
echo "[readiness] To recover (K8s auto-restores when /ready returns 200):"
echo "  kubectl set env deployment/${DEPLOY} READINESS_FAIL=false -n ${NAMESPACE}"
