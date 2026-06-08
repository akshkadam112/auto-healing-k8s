#!/usr/bin/env bash
# Simulate disk pressure — fill the node's disk with a large file.
# Healed by: Karpenter eviction manager (evicts pods, reclaims ephemeral storage)
# NOTE: uses minikube SSH. The fill is capped at 80% of disk to avoid actual corruption.
set -euo pipefail

NODE=${NODE:-minikube}
FILL_GB=${FILL_GB:-4}

echo "[disk-pressure] Writing ${FILL_GB}GB junk file on node ${NODE}..."
minikube ssh -n "${NODE}" -- \
  dd if=/dev/zero of=/tmp/disk-fill bs=1M count=$(( FILL_GB * 1024 )) status=progress

echo "[disk-pressure] Node should report DiskPressure shortly."
echo "  Watch: kubectl describe node ${NODE} | grep -A5 Conditions"
echo ""
echo "[disk-pressure] To recover:"
echo "  minikube ssh -n ${NODE} -- rm /tmp/disk-fill"
