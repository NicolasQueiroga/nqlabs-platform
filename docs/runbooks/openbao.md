# Runbook: OpenBao Secrets Backend

> **Status:** Full cutover complete. OpenBao KV (`kv/`) is the ONLY runtime
> secrets backend — every ExternalSecret uses ClusterSecretStore
> `nqlabs-openbao`. The legacy `nqlabs-1password` ClusterSecretStore has been
> retired. 1Password (`NQLabs` vault) is used at **bootstrap time only**:
> to escrow the root token + unseal keys, and as the source the bootstrap
> script reads to seed KV. Nothing reads 1Password at runtime.

## Overview

```text
OpenBao kv-v2 (kv/)
    ↑
External Secrets Operator v2.6.0
    ↑
ClusterSecretStore nqlabs-openbao
    ↑
ExternalSecret manifest in git
    →
Kubernetes Secret
```

Management cluster uses Kubernetes auth (ESO SA → OpenBao TokenReview).
Remote clusters (staging, production) use AppRole auth via the gateway URL.

## Architecture

- **OpenBao cluster:** 3 replicas, Raft integrated storage, ceph-block PVCs
- **Namespace:** `openbao` (management cluster)
- **Unseal:** **Automatic** — each pod has an auto-unseal sidecar that reads
  the 5 Shamir keys from the `openbao-unseal-keys` K8s Secret and unseals on
  startup (30s re-check loop). StatefulSet uses RollingUpdate. The
  `openbao-unseal-keys` Secret is a standalone bootstrap artifact (NOT
  ESO-managed, NOT in git — created by the bootstrap script). Keys are also
  escrowed in 1Password item `openbao-bootstrap` for DR.
- **Listener:** HTTP on :8200 (`tls_disable = 1`). TLS terminated at the
  Cilium Gateway edge with the Let's Encrypt wildcard cert.
- **PKI:** OpenBao does NOT serve PKI. cert-manager uses Let's Encrypt (edge)
  and its own internal CA. OpenBao serves KV secrets only.
- **Gateway:** `openbao.platform.nqlabs.network` (native OIDC login via Authentik)

## Bootstrap — automated (preferred)

After the management cluster and ArgoCD are up and the `openbao` app has
synced (pods Running), a single idempotent script brings the entire secrets
backend online. It is safe to run repeatedly and is the guarantee that
secrets roll out automatically on any cluster (re)creation:

```bash
export KUBECONFIG=clusters/nqlabs-management/bootstrap/talos/generated/kubeconfig
op signin            # 1Password CLI, NQLabs account
./scripts/openbao-bootstrap.sh
```

The script:

1. Waits for the OpenBao API.
2. If OpenBao is **uninitialized**: runs `bao operator init`, escrows the new
   root token + 5 unseal keys into 1Password item `openbao-bootstrap`, and
   creates the standalone `openbao-unseal-keys` K8s Secret that the auto-unseal
   sidecar consumes.
3. Ensures all pods are unsealed (fallback — the sidecar normally handles this).
4. Enables kv-v2 at `kv/` and the `kubernetes-management` auth method.
5. Configures Kubernetes auth **without** `token_reviewer_jwt` (durable fix —
   OpenBao uses its own auto-rotated pod SA token).
6. Writes the `allow-kv-read` policy and the `eso` role (bound to the
   `external-secrets/external-secrets` SA).
7. Seeds every platform secret into `kv/` from 1Password (the authoritative
   item→field map lives in `KV_ITEMS` at the top of the script).
8. Forces ESO to re-validate the `nqlabs-openbao` ClusterSecretStore.

Because ExternalSecrets retry until the store is Ready, apps that synced before
the script ran will pick up their secrets automatically once seeding completes.
No manual per-secret intervention is required.

> When adding a new secret to the platform, add its item+fields to the
> `KV_ITEMS` array in `scripts/openbao-bootstrap.sh` so cluster recreation
> re-seeds it.

## Bootstrap — manual (fallback reference)

The steps below document what the script automates, for debugging. Note the
script is the source of truth; some manual steps below (e.g. PKI) are no longer
part of the platform.

### 1. Deploy OpenBao

ArgoCD syncs the `openbao` Application (wave 3). Wait for pods Running:

```bash
kubectl -n openbao get pods -w
```

### 2. Initialize and unseal

```bash
# Exec into any OpenBao pod
kubectl -n openbao exec -it openbao-0 -- bao operator init

# Save the output (root token + unseal keys) to 1Password:
#   Item: openbao-bootstrap
#   Field: credential
#   Value: <root token>
#
#   Item: openbao-unseal-keys
#   Fields: key1, key2, key3, key4, key5
#   Values: <unseal key 1-5>

# Unseal each pod (3 of 5 keys needed)
kubectl -n openbao exec -it openbao-0 -- bao operator unseal <key1>
kubectl -n openbao exec -it openbao-0 -- bao operator unseal <key2>
kubectl -n openbao exec -it openbao-0 -- bao operator unseal <key3>

# Repeat for openbao-1 and openbao-2
```

### 3. Store root token in 1Password

Create 1Password item `openbao-bootstrap` with field `credential` containing
the root token. The bootstrap-token ExternalSecret will sync it to the
`openbao` namespace.

### 4. Configure Kubernetes auth (manual, after unseal)

After init + unseal, configure Kubernetes auth so ESO can connect.
**Do NOT set `token_reviewer_jwt`** — let OpenBao use its local pod SA token
(auto-rotated by Kubernetes, never expires).

```bash
ROOT_TOKEN=$(op item get openbao-bootstrap --vault NQLabs --field credential --reveal)

# Enable Kubernetes auth
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao auth enable -path=kubernetes-management kubernetes 2>/dev/null || true

# Configure auth (NO token_reviewer_jwt)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao write auth/kubernetes-management/config \
    kubernetes_host="https://kubernetes.default.svc:443" \
    disable_iss_validation=true \
    disable_local_ca_jwt=false

# Create eso role
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao write auth/kubernetes-management/role/eso \
    bound_service_account_names="external-secrets" \
    bound_service_account_namespaces="external-secrets" \
    policies="eso" ttl="1h"

# Create cert-manager role
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao write auth/kubernetes-management/role/cert-manager \
    bound_service_account_names="cert-manager" \
    bound_service_account_namespaces="cert-manager" \
    policies="cert-manager" ttl="1h"

# Enable KV v2
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao secrets enable -path=kv -version=2 kv 2>/dev/null || true

# Write policies
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao policy write default - <<'EOF'
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/renew-self" { capabilities = ["update"] }
EOF

kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao policy write eso - <<'EOF'
path "kv/data/*" { capabilities = ["read"] }
path "kv/metadata/*" { capabilities = ["list", "read"] }
EOF

kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao policy write cert-manager - <<'EOF'
path "pki/issue/*" { capabilities = ["create", "update"] }
path "pki/sign/*" { capabilities = ["create", "update"] }
path "pki/ca" { capabilities = ["read"] }
path "pki/crl" { capabilities = ["read"] }
EOF

# NOTE: OpenBao no longer serves PKI. cert-manager uses Let's Encrypt (edge)
# and its own internal CA. Do NOT enable a pki/ engine or the cert-manager
# role — those steps have been removed from the platform.

# Force ESO re-validate
kubectl annotate clustersecretstore nqlabs-openbao force-sync=$(date +%s) --overwrite
```

### 5. Bootstrap remote clusters

For each remote cluster (staging, production):

```bash
# Using the AppRole credentials from the bootstrap Job output:
kubectl --context=nqlabs-staging create secret generic openbao-approle \
  -n external-secrets \
  --from-literal=role-id=<role-id> \
  --from-literal=secret-id=<secret-id>

kubectl --context=nqlabs-production create secret generic openbao-approle \
  -n external-secrets \
  --from-literal=role-id=<role-id> \
  --from-literal=secret-id=<secret-id>
```

### 6. Seed secrets into OpenBao KV

Migrate all secrets from 1Password to OpenBao KV:

```bash
export BAO_ADDR=https://openbao.openbao.svc.cluster.local:8200
export BAO_CACERT=/path/to/ca.crt
export BAO_TOKEN=<root-token>

# Example: migrate grafana-oidc
bao kv put kv/grafana-oidc client_secret=<value>

# Example: migrate cloudflare-dns-token
bao kv put kv/cloudflare-dns-token credential=<value>

# Repeat for all secrets (see ExternalSecret manifests for the full list)
```

### 7. Verify canary

```bash
# Seed canary
bao kv put kv/canary/openbao-eso value="hello-from-openbao"

# Check ExternalSecret
kubectl -n openbao get externalsecret openbao-canary
# Should show SecretSynced=True
```

### 8. Verify all ExternalSecrets

```bash
kubectl get externalsecret -A
# All should show SecretSynced=True
```

## Disaster Recovery

### Backup (Raft snapshot)

Take a snapshot of the Raft data:

```bash
kubectl -n openbao exec -it openbao-0 -- bao operator raft snapshot save /openbao/audit/snapshot.snap
kubectl -n openbao cp openbao-0:/openbao/audit/snapshot.snap ./openbao-snapshot-$(date +%Y%m%d).snap
```

Schedule periodic snapshots via cron or Velero file backup.

### Restore from snapshot

#### Scenario: PVC loss (all data lost)

1. Delete the OpenBao StatefulSet (keeps PVCs):

   ```bash
   kubectl -n openbao delete statefulset openbao
   ```

2. Delete PVCs (data is gone — this is the DR scenario):

   ```bash
   kubectl -n openbao delete pvc data-openbao-0 data-openbao-1 data-openbao-2
   kubectl -n openbao delete pvc audit-openbao-0 audit-openbao-1 audit-openbao-2
   ```

3. Let ArgoCD recreate the StatefulSet. Wait for pods:

   ```bash
   kubectl -n openbao get pods -w
   ```

4. Initialize OpenBao with the snapshot:

   ```bash
   kubectl -n openbao cp ./openbao-snapshot-latest.snap openbao-0:/tmp/snapshot.snap
   kubectl -n openbao exec -it openbao-0 -- bao operator raft restore /tmp/snapshot.snap
   ```

5. Unseal all pods (step 2 above).

6. Verify:

   ```bash
   bao status
   bao secrets list
   bao auth list
   kubectl get externalsecret -A
   ```

#### Scenario: Single pod failure

Raft tolerates 1 pod failure with 3 replicas. The failed pod will rejoin
automatically when it restarts:

```bash
kubectl -n openbao delete pod openbao-0
# Pod restarts, rejoins Raft, and catches up
```

### Rekey (rotate unseal keys)

```bash
bao operator rekey -init -key-shares=5 -key-threshold=3
bao operator rekey
# Save new keys to 1Password (item: openbao-unseal-keys)
```

## Post-migration cleanup — DONE

The management cluster cutover is complete:

### 1. Retire nqlabs-1password ClusterSecretStore — DONE

`infrastructure/security/external-secrets/cluster-secret-store.yaml` was
removed from git and the `nqlabs-1password` ClusterSecretStore pruned by
ArgoCD. The `onepassword-service-account-token` Secret in the
`external-secrets` namespace can be deleted (no runtime consumer). The
`openbao-unseal-keys` ExternalSecret was also retired — its target Secret was
orphaned (ownerReference removed) into a standalone bootstrap artifact that
the auto-unseal sidecar reads and the bootstrap script recreates.

### 2. Retire selfsigned-bootstrap and nqlabs-internal-ca issuers

Remove the `selfsigned-bootstrap` ClusterIssuer, `nqlabs-internal-ca`
Certificate, and `nqlabs-internal-ca` ClusterIssuer from
`infrastructure/security/cert-manager/cluster-issuers.yaml`.

Update the OpenBao TLS Certificate `issuerRef` to `nqlabs-openbao-pki`.

### 3. Revoke root token (optional)

The bootstrap config Job remains in the repo for future re-inits.
Do NOT remove it — it configures Kubernetes auth correctly without
`token_reviewer_jwt`, preventing recurring Degraded status.

Revoke the root token after bootstrap is verified:

```bash
bao token revoke -self
```

Rotate the 1Password `openbao-bootstrap` item.

### 4. Remove canary

```bash
bao kv delete kv/canary/openbao-eso
```

Remove `infrastructure/security/openbao/manifests/canary-externalsecret.yaml`.

## Verification commands

```bash
# OpenBao status
kubectl -n openbao exec openbao-0 -- bao status

# ClusterSecretStore status
kubectl get clustersecretstore nqlabs-openbao
kubectl get clustersecretstore -A

# ExternalSecret status (all clusters)
kubectl get externalsecret -A

# OpenBao audit log (stdout)
kubectl -n openbao logs openbao-0 | grep audit

# Raft cluster status
kubectl -n openbao exec openbao-0 -- bao operator raft list-peers
```

## Common failure modes

### OpenBao sealed after restart

Pods auto-unseal via the sidecar (reads `openbao-unseal-keys` Secret). If a pod
stays sealed, check the sidecar container logs and that the
`openbao-unseal-keys` Secret exists with 5 keys. Manual fallback (3 of 5 keys
from 1Password item `openbao-bootstrap`):

```bash
kubectl -n openbao exec -it openbao-0 -c openbao -- bao operator unseal <key1>
kubectl -n openbao exec -it openbao-0 -c openbao -- bao operator unseal <key2>
kubectl -n openbao exec -it openbao-0 -c openbao -- bao operator unseal <key3>
```

If the `openbao-unseal-keys` Secret is missing entirely, re-run
`./scripts/openbao-bootstrap.sh` (it recreates it on a fresh init, or you can
recreate it manually from the 1Password `openbao-bootstrap` item).

### ExternalSecret stuck in SecretSynced=False

Check:

```bash
kubectl describe externalsecret <name> -n <namespace>
kubectl get clustersecretstore nqlabs-openbao
```

Likely causes:
- OpenBao sealed
- AppRole secret expired (remote clusters)
- KV path doesn't exist (seed the secret)
- Network policy blocking ESO → OpenBao

### ClusterSecretStore nqlabs-openbao Ready=False (unable to create client)

**Most common cause:** `token_reviewer_jwt` expired. After OpenBao re-init,
if the Kubernetes auth config was set with a manually-created SA token
(`kubectl create token -n openbao openbao --duration=1h`), that token
expires after 1 hour. OpenBao can't validate ESO login tokens → CSS goes
`Ready: False` → ArgoCD app shows Degraded.

**Fix (durable):** Clear `token_reviewer_jwt` so OpenBao uses its local
pod's projected SA token (auto-rotated by Kubernetes):

```bash
kubectl exec -n openbao openbao-0 -- bao write auth/kubernetes-management/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  disable_iss_validation=true \
  disable_local_ca_jwt=false \
  token_reviewer_jwt=""

# Force ESO to re-validate
kubectl annotate clustersecretstore nqlabs-openbao force-sync=$(date +%s) --overwrite
```

**Fix (emergency, non-durable):** Re-set with a fresh 1h token (will break
again after 1h):

```bash
OPENBAO_SA_TOKEN=$(kubectl create token -n openbao openbao --duration=1h)
kubectl exec -n openbao openbao-0 -- bao write auth/kubernetes-management/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  token_reviewer_jwt="$OPENBAO_SA_TOKEN" \
  disable_iss_validation=true
```

**Do NOT set `token_reviewer_jwt` with a short-lived SA token.** The
bootstrap config runbook (see step 4 above)
configures auth correctly without `token_reviewer_jwt`.

### cert-manager can't issue cert from nqlabs-openbao-pki

Check:

```bash
kubectl describe clusterissuer nqlabs-openbao-pki
kubectl get secret openbao-pki-ca -n cert-manager
```

Likely causes:
- OpenBao sealed
- cert-manager SA not bound in OpenBao Kubernetes auth
- PKI CA not yet generated (step 4 not run)
- caBundleSecretRef secret missing or stale
