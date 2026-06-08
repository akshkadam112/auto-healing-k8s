#!/usr/bin/env bash
# Simulate traffic spike / high latency — blast the sample-app with requests.
# Healed by: HPA scales out pods when CPU utilization exceeds 60%
# Requires: hey (https://github.com/rakyll/hey) or curl fallback
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}
DEPLOY=${DEPLOY:-sample-app}
DURATION=${DURATION:-60}     # seconds
CONCURRENCY=${CONCURRENCY:-50}

SVC_URL=$(kubectl get svc "${DEPLOY}" -n "${NAMESPACE}" \
  -o jsonpath='http://{.spec.clusterIP}:{.spec.ports[0].port}/')

echo "[traffic-spike] Target: ${SVC_URL}"
echo "[traffic-spike] Concurrency: ${CONCURRENCY}, Duration: ${DURATION}s"
echo ""
echo "  Watch HPA scale out: kubectl get hpa -n ${NAMESPACE} -w"
echo "  Watch pods: kubectl get pods -n ${NAMESPACE} -w"
echo ""

if command -v hey &>/dev/null; then
  hey -c "${CONCURRENCY}" -z "${DURATION}s" "${SVC_URL}"
else
  echo "[traffic-spike] 'hey' not found — using parallel curl (install hey for better metrics)"
  seq "${CONCURRENCY}" | xargs -P "${CONCURRENCY}" -I{} \
    bash -c "for i in \$(seq 200); do curl -sf '${SVC_URL}' -o /dev/null; done" &
  sleep "${DURATION}"
  kill %1 2>/dev/null || true
fi

echo "[traffic-spike] Done. HPA will scale back down after ~5 minutes of low traffic."
