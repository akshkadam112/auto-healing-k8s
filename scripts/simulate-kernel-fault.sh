#!/usr/bin/env bash
# Simulate a kernel / OS fault using node-problem-detector's event injection.
# NPD reads /dev/kmsg or a log file and emits NodeConditions based on patterns.
# Here we inject a synthetic KernelDeadlock condition directly via kubectl.
# Healed by: NPD taints the node → pods rescheduled by the scheduler.
set -euo pipefail

NODE=${NODE:-minikube}

echo "[kernel-fault] Injecting KernelDeadlock condition on node ${NODE}..."

kubectl patch node "${NODE}" --type=json -p='[
  {
    "op": "add",
    "path": "/status/conditions/-",
    "value": {
      "type": "KernelDeadlock",
      "status": "True",
      "reason": "SimulatedKernelDeadlock",
      "message": "Synthetic kernel deadlock injected by simulate-kernel-fault.sh",
      "lastHeartbeatTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "lastTransitionTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }
  }
]' --subresource=status 2>/dev/null || \
  echo "[kernel-fault] Direct status patch requires admin; try: kubectl taint node ${NODE} kernel-deadlock=true:NoSchedule"

kubectl taint node "${NODE}" kernel-deadlock=true:NoSchedule --overwrite || true

echo "[kernel-fault] Node ${NODE} tainted. New pods will not schedule here."
echo "  Watch: kubectl get pods -n demo -w"
echo ""
echo "[kernel-fault] To recover:"
echo "  kubectl taint node ${NODE} kernel-deadlock=true:NoSchedule-"
