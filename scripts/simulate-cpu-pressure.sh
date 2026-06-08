#!/usr/bin/env bash
# Simulate CPU / memory pressure — run stress-ng inside the node via minikube SSH.
# Healed by: Karpenter eviction thresholds (evicts best-effort pods)
set -euo pipefail

NODE=${NODE:-minikube}
DURATION=${DURATION:-60}   # seconds

echo "[cpu-pressure] Running stress-ng for ${DURATION}s on node ${NODE}..."
minikube ssh -n "${NODE}" -- \
  bash -c "which stress-ng || sudo apt-get install -y stress-ng -q" 2>/dev/null || true

minikube ssh -n "${NODE}" -- \
  stress-ng --cpu 0 --vm 2 --vm-bytes 80% --timeout "${DURATION}s" &

echo "[cpu-pressure] CPU and memory stress running for ${DURATION}s."
echo "  Watch: kubectl top nodes"
echo "  Watch: kubectl get pods -n demo -w"
echo ""
echo "[cpu-pressure] Stress exits automatically after ${DURATION}s."
