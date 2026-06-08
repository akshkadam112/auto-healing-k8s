#!/usr/bin/env bash
# Simulate TLS cert expiry — create a cert-manager Certificate with a 2-minute duration
# so it expires almost immediately, then watch cert-manager auto-renew it.
# Healed by: cert-manager (renews at 2/3 of lifetime → ~80s after issue)
set -euo pipefail

NAMESPACE=${NAMESPACE:-demo}

echo "[tls-expiry] Creating a short-lived Certificate (2m duration)..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: short-lived-cert
  namespace: ${NAMESPACE}
spec:
  secretName: short-lived-cert-tls
  duration: 2m          # expires in 2 minutes
  renewBefore: 80s      # cert-manager renews at T-80s → almost immediately
  dnsNames:
    - sample-app.demo.svc.cluster.local
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF

echo "[tls-expiry] Certificate created. cert-manager will renew it automatically."
echo "  Watch: kubectl get certificate short-lived-cert -n ${NAMESPACE} -w"
echo "  Watch events: kubectl describe certificate short-lived-cert -n ${NAMESPACE}"
echo ""
echo "[tls-expiry] To clean up:"
echo "  kubectl delete certificate short-lived-cert -n ${NAMESPACE}"
echo "  kubectl delete secret short-lived-cert-tls -n ${NAMESPACE}"
