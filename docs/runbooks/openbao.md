# Runbook: OpenBao Secrets Backend

> **Status:** Phase 1-10 full cutover. OpenBao replaces 1Password as the
> runtime secrets backend. 1Password remains for bootstrap escrow only
> (root token, unseal keys).

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
- **Unseal:** Manual (Shamir) — unseal keys escrowed in 1Password
- **TLS:** Internal cert from cert-manager (nqlabs-internal-ca → nqlabs-openbao-pki)
- **Gateway:** `openbao.platform.nqlabs.network` (Let's Encrypt wildcard at gateway)

## Bootstrap (one-time)

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

### 4. Run the bootstrap config Job

```bash
kubectl -n openbao create job --from=job/openbao-bootstrap-config openbao-bootstrap-config-manual
kubectl -n openbao logs job/openbao-bootstrap-config-manual -f
```

The Job outputs:
- AppRole credentials for staging and production clusters
- Verification commands

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

## Post-migration cleanup

After all clusters are verified on OpenBao:

### 1. Retire nqlabs-1password ClusterSecretStore

Remove `infrastructure/security/external-secrets/cluster-secret-store.yaml`
and the `onepassword-service-account-token` Secret from all clusters.

### 2. Retire selfsigned-bootstrap and nqlabs-internal-ca issuers

Remove the `selfsigned-bootstrap` ClusterIssuer, `nqlabs-internal-ca`
Certificate, and `nqlabs-internal-ca` ClusterIssuer from
`infrastructure/security/cert-manager/cluster-issuers.yaml`.

Update the OpenBao TLS Certificate `issuerRef` to `nqlabs-openbao-pki`.

### 3. Remove bootstrap Job and ExternalSecret

Remove:
- `infrastructure/security/openbao/manifests/bootstrap-config-job.yaml`
- `infrastructure/security/openbao/manifests/bootstrap-token-externalsecret.yaml`

Revoke the root token:

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

OpenBao uses manual unseal (Shamir). After any pod restart, unseal with
3 of 5 keys:

```bash
kubectl -n openbao exec -it openbao-0 -- bao operator unseal <key1>
kubectl -n openbao exec -it openbao-0 -- bao operator unseal <key2>
kubectl -n openbao exec -it openbao-0 -- bao operator unseal <key3>
```

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

### cert-manager can't issue cert from nqlabs-openbao-pki

Check:

```bash
kubectl describe clusterissuer nqlabs-openbao-pki
kubectl get secret openbao-pki-ca -n cert-manager
```

Likely causes:
- OpenBao sealed
- cert-manager SA not bound in OpenBao Kubernetes auth
- PKI CA not yet generated (bootstrap Job not run)
- caBundleSecretRef secret missing or stale
