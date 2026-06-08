#!/usr/bin/env bash
# Measure Mean Time To Recovery (MTTR) for a given failure simulation.
#
# Usage:
#   ./measure-mttr.sh crashloop
#   ./measure-mttr.sh oomkill
#   ./measure-mttr.sh stuck-rollout
#
# Prints: failure_injected_at, recovered_at, mttr_seconds
set -euo pipefail

SCENARIO=${1:-crashloop}
NAMESPACE=${NAMESPACE:-demo}
DEPLOY=${DEPLOY:-sample-app}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[mttr] Starting MTTR measurement for scenario: ${SCENARIO}"
echo "[mttr] Namespace: ${NAMESPACE}  Deployment: ${DEPLOY}"
echo ""

# ── Wait until all pods are Ready before injecting fault ──────────────────────
echo "[mttr] Waiting for deployment to be fully healthy before injection..."
kubectl rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}" --timeout=120s

FAULT_TIME=$(date +%s)
echo "[mttr] Fault injection started at: $(date -d @"${FAULT_TIME}" '+%Y-%m-%d %H:%M:%S')"

# ── Inject the fault ──────────────────────────────────────────────────────────
case "${SCENARIO}" in
  crashloop)
    kubectl set env deployment/"${DEPLOY}" CRASH_ON_START=true -n "${NAMESPACE}"
    ;;
  oomkill)
    kubectl set env deployment/"${DEPLOY}" MEMORY_HOG_MB=200 -n "${NAMESPACE}"
    ;;
  stuck-rollout)
    kubectl set env deployment/"${DEPLOY}" SLOW_START_SECONDS=120 -n "${NAMESPACE}"
    ;;
  liveness)
    kubectl set env deployment/"${DEPLOY}" LIVENESS_FAIL=true -n "${NAMESPACE}"
    ;;
  readiness)
    kubectl set env deployment/"${DEPLOY}" READINESS_FAIL=true -n "${NAMESPACE}"
    ;;
  *)
    echo "Unknown scenario: ${SCENARIO}"
    echo "Valid: crashloop | oomkill | stuck-rollout | liveness | readiness"
    exit 1
    ;;
esac

echo "[mttr] Fault injected. Polling for recovery..."

# ── Poll until the deployment is fully ready again ────────────────────────────
RECOVERED=false
for i in $(seq 1 120); do
  sleep 5
  READY=$(kubectl get deployment "${DEPLOY}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get deployment "${DEPLOY}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

  echo "[mttr] t+$((i * 5))s — ready=${READY:-0}/${DESIRED}"

  if [[ "${READY:-0}" -ge "${DESIRED}" ]]; then
    RECOVERED=true
    break
  fi
done

RECOVERY_TIME=$(date +%s)
MTTR=$(( RECOVERY_TIME - FAULT_TIME ))

echo ""
if ${RECOVERED}; then
  echo "✓ RECOVERED"
else
  echo "✗ DID NOT RECOVER within 10 minutes"
fi

echo "────────────────────────────────"
printf "%-25s %s\n" "Scenario:"       "${SCENARIO}"
printf "%-25s %s\n" "Fault injected:" "$(date -d @"${FAULT_TIME}" '+%Y-%m-%d %H:%M:%S')"
printf "%-25s %s\n" "Recovered at:"   "$(date -d @"${RECOVERY_TIME}" '+%Y-%m-%d %H:%M:%S')"
printf "%-25s %ds\n" "MTTR:"          "${MTTR}"
echo "────────────────────────────────"
