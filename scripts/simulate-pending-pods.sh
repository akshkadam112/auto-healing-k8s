#!/usr/bin/env bash
# Simulate pending pods — deploy a pod requesting more CPU/memory than any node has.
# Healed by: Karpenter provisions a new node to satisfy the resource request.
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}

echo "[pending-pods] Deploying a resource-hungry pod that cannot be scheduled..."

kubectl apply -f - -n "${NAMESPACE}" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pending-pod-sim
  labels:
    simulation: pending-pods
spec:
  containers:
    - name: pause
      image: registry.k8s.io/pause:3.9
      resources:
        requests:
          cpu: "32"         # more cores than minikube node has
          memory: "64Gi"    # more RAM than minikube node has
  restartPolicy: Never
EOF

echo "[pending-pods] Pod created — it will stay Pending until Karpenter provisions capacity."
echo "  Watch: kubectl get pods -n ${NAMESPACE} pending-pod-sim -w"
echo "  Watch nodes: kubectl get nodes -w"
echo ""
echo "[pending-pods] To clean up:"
echo "  kubectl delete pod pending-pod-sim -n ${NAMESPACE}"
