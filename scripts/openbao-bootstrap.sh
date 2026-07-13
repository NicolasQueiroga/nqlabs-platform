#!/usr/bin/env bash
#
# openbao-bootstrap.sh — idempotent OpenBao bootstrap + KV seed for the
# nqlabs-management cluster. This is the single command that makes the
# platform's secrets backend come up automatically after a cluster
# (re)creation. Safe to run repeatedly.
#
# What it does (all steps are idempotent):
#   1. Waits for the OpenBao API to respond.
#   2. If OpenBao is uninitialized: `bao operator init`, then escrows the
#      generated root token + 5 unseal keys into 1Password (item
#      `openbao-bootstrap`) AND creates the `openbao-unseal-keys` K8s Secret
#      that the auto-unseal sidecar consumes.
#   3. Ensures all pods are unsealed (the sidecar normally does this; we
#      unseal directly as a fallback).
#   4. Enables kv-v2 at kv/ and the kubernetes-management auth method.
#   5. Configures kubernetes auth WITHOUT token_reviewer_jwt (durable fix —
#      OpenBao uses its own auto-rotated pod SA token).
#   6. Writes the allow-kv-read policy and the `eso` role (bound to the
#      external-secrets SA).
#   7. Seeds every platform secret into kv/ from 1Password.
#   8. Forces ESO to re-validate the ClusterSecretStore.
#
# Requirements: kubectl (KUBECONFIG set to the mgmt cluster), op (1Password
# CLI, signed in to the NQLabs account), python3.
#
# Root of trust: the ONLY external dependency is the 1Password `NQLabs`
# vault, used at bootstrap time only (never at runtime). Runtime secret
# reads are served entirely by OpenBao KV.
set -euo pipefail

NS=openbao
POD=openbao-0
VAULT=NQLabs
BOOTSTRAP_ITEM=openbao-bootstrap
BAO_ADDR_INT=http://127.0.0.1:8200
ESO_SA_NS=external-secrets
ESO_SA_NAME=external-secrets

# item -> space-separated field list (mirrors the ExternalSecret remoteRefs).
# Keep in sync with the ExternalSecret manifests in git.
KV_ITEMS=(
  "argocd-oidc:client_secret"
  "authentik-postgres:password"
  "authentik-pg-backup-s3:ACCESS_KEY_ID SECRET_ACCESS_KEY"
  "authentik:secret_key bootstrap_password bootstrap_token redis_password"
  "ironic-auth:username password"
  "cloudflare-dns-token:credential"
  "alertmanager-discord:webhook_url"
  "ironic-api-credentials:username password htpasswd"
  "proxmox-bmc:username password"
  "gatus-oidc:client_secret"
  "grafana-oidc:client_secret"
  "thanos-objstore:access_key secret_key"
  "tailscale-key:username credential"
  "velero-aws:access-key-id secret-access-key"
  "velero-azure:storage-key"
  "velero-rgw-credentials:aws_access_key_id aws_secret_access_key"
  "cloudflared-tunnel:token"
  "openbao-oidc:client_secret"
)

log() { printf '\033[1;34m[openbao-bootstrap]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[openbao-bootstrap] ERROR:\033[0m %s\n' "$*" >&2; }

kexec() { kubectl exec -n "$NS" "$POD" -c openbao -- env BAO_ADDR="$BAO_ADDR_INT" "$@"; }
kexec_t() { kubectl exec -n "$NS" "$POD" -c openbao -- env BAO_ADDR="$BAO_ADDR_INT" BAO_TOKEN="$ROOT_TOKEN" "$@"; }

require() { command -v "$1" >/dev/null 2>&1 || { err "missing required tool: $1"; exit 1; }; }
require kubectl; require op; require python3

# ---------------------------------------------------------------------------
# 1. Wait for the API
# ---------------------------------------------------------------------------
log "waiting for OpenBao API on $POD ..."
for i in $(seq 1 60); do
  if kexec bao status >/dev/null 2>&1 || [ $? -eq 2 ]; then break; fi
  sleep 5
  [ "$i" = 60 ] && { err "OpenBao API never responded"; exit 1; }
done

INITIALIZED=$(kexec bao status -format=json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["initialized"])' 2>/dev/null || echo "false")

# ---------------------------------------------------------------------------
# 2. Initialize (only if fresh) and escrow keys
# ---------------------------------------------------------------------------
if [ "$INITIALIZED" != "True" ] && [ "$INITIALIZED" != "true" ]; then
  log "OpenBao is UNINITIALIZED — running operator init"
  INIT_JSON=$(kexec bao operator init -key-shares=5 -key-threshold=3 -format=json)
  ROOT_TOKEN=$(echo "$INIT_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["root_token"])')
  mapfile -t KEYS < <(echo "$INIT_JSON" | python3 -c 'import sys,json;[print(k) for k in json.load(sys.stdin)["unseal_keys_b64"]]')

  log "escrowing root token + unseal keys into 1Password item '$BOOTSTRAP_ITEM'"
  op item edit "$BOOTSTRAP_ITEM" --vault "$VAULT" \
    "credential[password]=$ROOT_TOKEN" \
    "unseal_key_1[password]=${KEYS[0]}" \
    "unseal_key_2[password]=${KEYS[1]}" \
    "unseal_key_3[password]=${KEYS[2]}" \
    "unseal_key_4[password]=${KEYS[3]}" \
    "unseal_key_5[password]=${KEYS[4]}" >/dev/null

  log "creating openbao-unseal-keys K8s Secret (feeds the auto-unseal sidecar)"
  kubectl create secret generic openbao-unseal-keys -n "$NS" \
    --from-literal=unseal_key_1="${KEYS[0]}" \
    --from-literal=unseal_key_2="${KEYS[1]}" \
    --from-literal=unseal_key_3="${KEYS[2]}" \
    --from-literal=unseal_key_4="${KEYS[3]}" \
    --from-literal=unseal_key_5="${KEYS[4]}" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  log "OpenBao already initialized — reading root token from 1Password"
  ROOT_TOKEN=$(op item get "$BOOTSTRAP_ITEM" --vault "$VAULT" --fields credential --reveal)
fi

[ -n "${ROOT_TOKEN:-}" ] || { err "no root token available"; exit 1; }

# ---------------------------------------------------------------------------
# 3. Ensure every pod is unsealed (fallback if the sidecar hasn't yet)
# ---------------------------------------------------------------------------
K1=$(op item get "$BOOTSTRAP_ITEM" --vault "$VAULT" --fields unseal_key_1 --reveal)
K2=$(op item get "$BOOTSTRAP_ITEM" --vault "$VAULT" --fields unseal_key_2 --reveal)
K3=$(op item get "$BOOTSTRAP_ITEM" --vault "$VAULT" --fields unseal_key_3 --reveal)
for p in openbao-0 openbao-1 openbao-2; do
  SEALED=$(kubectl exec -n "$NS" "$p" -c openbao -- env BAO_ADDR="$BAO_ADDR_INT" bao status -format=json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["sealed"])' 2>/dev/null || echo "unknown")
  if [ "$SEALED" = "True" ] || [ "$SEALED" = "true" ]; then
    log "unsealing $p"
    for k in "$K1" "$K2" "$K3"; do
      kubectl exec -n "$NS" "$p" -c openbao -- env BAO_ADDR="$BAO_ADDR_INT" bao operator unseal "$k" >/dev/null || true
    done
  fi
done

# ---------------------------------------------------------------------------
# 4-6. Idempotent engine / auth / policy / role config
# ---------------------------------------------------------------------------
log "ensuring kv-v2 engine at kv/"
kexec_t bao secrets enable -path=kv -version=2 kv 2>/dev/null || true

log "ensuring kubernetes-management auth method"
kexec_t bao auth enable -path=kubernetes-management kubernetes 2>/dev/null || true

log "configuring kubernetes auth (NO token_reviewer_jwt — durable fix)"
kexec_t bao write auth/kubernetes-management/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  disable_iss_validation=true \
  disable_local_ca_jwt=false \
  token_reviewer_jwt="" >/dev/null

log "writing allow-kv-read policy"
kubectl exec -i -n "$NS" "$POD" -c openbao -- env BAO_ADDR="$BAO_ADDR_INT" BAO_TOKEN="$ROOT_TOKEN" \
  bao policy write allow-kv-read - <<'POLICY'
path "kv/data/*"     { capabilities = ["read"] }
path "kv/metadata/*" { capabilities = ["read", "list"] }
POLICY

log "ensuring default policy retains token self-management"
kubectl exec -i -n "$NS" "$POD" -c openbao -- env BAO_ADDR="$BAO_ADDR_INT" BAO_TOKEN="$ROOT_TOKEN" \
  bao policy write default - <<'POLICY'
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/renew-self"  { capabilities = ["update"] }
POLICY

log "writing eso role"
kexec_t bao write auth/kubernetes-management/role/eso \
  bound_service_account_names="$ESO_SA_NAME" \
  bound_service_account_namespaces="$ESO_SA_NS" \
  token_policies="allow-kv-read" ttl="1h" >/dev/null

# ---------------------------------------------------------------------------
# 7. Seed KV from 1Password (idempotent — overwrites)
# ---------------------------------------------------------------------------
log "seeding KV from 1Password ($VAULT vault)"
SEEDED=0
for entry in "${KV_ITEMS[@]}"; do
  item="${entry%%:*}"
  fields="${entry#*:}"
  json="{"
  first=1
  for f in $fields; do
    val=$(op read "op://$VAULT/$item/$f")
    [ -n "$val" ] || { err "empty value for $item/$f"; exit 1; }
    esc=$(printf '%s' "$val" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')
    [ $first -eq 1 ] || json+=","
    json+="\"$f\":$esc"
    first=0
  done
  json+="}"
  printf '%s' "$json" | kubectl exec -i -n "$NS" "$POD" -c openbao -- \
    env BAO_ADDR="$BAO_ADDR_INT" BAO_TOKEN="$ROOT_TOKEN" \
    sh -c "cat > /tmp/s.json && bao kv put kv/$item @/tmp/s.json >/dev/null && rm -f /tmp/s.json"
  log "  seeded kv/$item ($fields)"
  SEEDED=$((SEEDED+1))
done
log "seeded $SEEDED items into kv/"

# ---------------------------------------------------------------------------
# 8. Force ESO to re-validate
# ---------------------------------------------------------------------------
log "forcing ESO to re-validate ClusterSecretStore nqlabs-openbao"
kubectl annotate clustersecretstore nqlabs-openbao force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || true

log "DONE. OpenBao is initialized, unsealed, configured, and seeded."
log "Verify: kubectl get clustersecretstore nqlabs-openbao ; kubectl get externalsecret -A"
