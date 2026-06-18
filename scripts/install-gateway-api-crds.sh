#!/usr/bin/env bash
# install-gateway-api-crds.sh
#
# Installs Gateway API CRDs compatible with Cilium 1.19.x.
#
# Version: v1.2.1 (standard + experimental)
# Compatibility note: Cilium 1.19.x expects TLSRoute at gateway.networking.k8s.io/v1alpha2.
# Gateway API v1.5.x promotes TLSRoute to v1 and sets v1alpha2 served=false, breaking Cilium.
# Use v1.2.1 (or patch v1alpha2 served=true after installing a newer version).
#
# Usage:
#   ./scripts/install-gateway-api-crds.sh
#
# Idempotent — safe to re-run.

set -euo pipefail

GATEWAY_API_VERSION="v1.2.1"
BASE_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading Gateway API CRDs ${GATEWAY_API_VERSION}..."
curl -sL "${BASE_URL}/standard-install.yaml"     -o "${TMP_DIR}/standard-install.yaml"
curl -sL "${BASE_URL}/experimental-install.yaml" -o "${TMP_DIR}/experimental-install.yaml"

echo "Applying standard CRDs..."
kubectl apply --server-side -f "${TMP_DIR}/standard-install.yaml"

echo "Applying experimental CRDs (includes TLSRoute v1alpha2)..."
kubectl apply --server-side -f "${TMP_DIR}/experimental-install.yaml"

echo ""
echo "Installed Gateway API CRDs:"
kubectl get crd | grep gateway.networking.k8s.io

echo ""
echo "Verifying TLSRoute v1alpha2 is served (required by Cilium 1.19.x)..."
V1ALPHA2_SERVED=$(kubectl get crd tlsroutes.gateway.networking.k8s.io \
  -o jsonpath='{range .spec.versions[?(@.name=="v1alpha2")]}{.served}{end}')

if [ "${V1ALPHA2_SERVED}" != "true" ]; then
  echo "WARNING: TLSRoute v1alpha2 is not served — patching to enable it (Cilium compatibility)"
  kubectl patch crd tlsroutes.gateway.networking.k8s.io --type=json \
    -p='[{"op":"replace","path":"/spec/versions/1/served","value":true}]'
  echo "Patched."
fi

echo ""
echo "Done. Gateway API CRD versions:"
kubectl get crd tlsroutes.gateway.networking.k8s.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{"\n"}{end}'
