#!/usr/bin/env bash
# Simulate Node NotReady — stop the kubelet process on a minikube node.
# Healed by: Karpenter (cordon + drain + replace node)
# NOTE: on minikube this uses the minikube SSH interface.
set -euo pipefail

NODE=${NODE:-minikube}

echo "[node-notready] Stopping kubelet on node ${NODE} to simulate NotReady..."
minikube ssh -n "${NODE}" -- sudo systemctl stop kubelet

echo "[node-notready] Node will transition to NotReady within ~40s."
echo "  Watch: kubectl get nodes -w"
echo ""
echo "[node-notready] To recover (Karpenter replaces the node in production):"
echo "  minikube ssh -n ${NODE} -- sudo systemctl start kubelet"
