# Runbook: Secrets Management

> **Status:** Live three-cluster service factory (management/staging/production). Current architecture: [../docs/architecture/service-factory.md](../docs/architecture/service-factory.md). Single-cluster/desktop-lab references below are historical.


## Overview

Secrets are never committed to git. Git stores only references to secret material.
External Secrets Operator (ESO) reads those references and creates Kubernetes Secrets
inside the cluster.

Current Phase 0 backend:

```text
1Password item/field
    ↓
ExternalSecret manifest in git
    ↓
External Secrets Operator v2.6.0
    ↓
ClusterSecretStore nqlabs-1password
    ↓
Kubernetes Secret
```

This platform uses the **1Password SDK provider**, not 1Password Connect. Nick's
personal 1Password plan does not include Connect, and the SDK provider works with a
service account token.

## Bootstrap secret

ESO needs one manual bootstrap secret:

| Namespace | Secret | Purpose |
|-----------|--------|---------|
| `external-secrets` | `onepassword-service-account-token` | Token used by ESO's 1Password SDK provider |

The token value lives in 1Password and is applied manually once during bootstrap.
Never commit it.

## Rotate the 1Password service account token

Rotation is manual because the token is the trust root ESO uses to read every
other secret.

1. Create a new 1Password service account token with access to the `NQLabs` vault.
2. Store the new token in 1Password item `Service Account Auth Token: NQ Labs`,
   field `credential`.
3. Update the bootstrap Secret on every cluster that runs ESO:

   ```bash
   op item get "Service Account Auth Token: NQ Labs" \
     --account my.1password.com --fields credential --format json \
     | python3 -c "import json,sys; sys.stdout.write(json.load(sys.stdin)['value'])" \
     | kubectl -n external-secrets create secret generic onepassword-service-account-token \
         --from-file=token=/dev/stdin \
         --dry-run=client -o yaml \
     | kubectl apply -f -
   ```

4. Restart ESO so all replicas pick up the token immediately:

   ```bash
   kubectl -n external-secrets rollout restart deploy/external-secrets
   kubectl -n external-secrets rollout restart deploy/external-secrets-webhook
   kubectl -n external-secrets rollout restart deploy/external-secrets-cert-controller
   ```

5. Verify:

   ```bash
   kubectl get clustersecretstore nqlabs-1password
   kubectl get externalsecret -A
   ```

6. Revoke the old service account token in 1Password only after all clusters show
   `ClusterSecretStore/nqlabs-1password` Ready/Valid.

## ClusterSecretStore

Current store:

```bash
kubectl get clustersecretstore nqlabs-1password
```

Expected:

```text
NAME                AGE   STATUS   CAPABILITIES   READY
nqlabs-1password    ...   Valid    ReadWrite      True
```

## ExternalSecret key format

Use item/field format:

```yaml
remoteRef:
  key: grafana/password
```

Examples:

| Secret | 1Password reference |
|--------|---------------------|
| Grafana admin user | `grafana/username` |
| Grafana admin password | `grafana/password` |
| Tailscale OAuth client ID | `tailscale-key/username` |
| Tailscale OAuth client secret | `tailscale-key/credential` |

Do **not** use `op://...` URIs in this provider. Do **not** use item names without a
field name.

## Add a new secret-backed Kubernetes Secret

1. Create or update the 1Password item in the `NQLabs` vault.
2. Add an `ExternalSecret` manifest to git.
3. Reference `ClusterSecretStore/nqlabs-1password`.
4. Sync the owning ArgoCD app.
5. Verify ESO created the Secret.

Example:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example-credentials
  namespace: example
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: nqlabs-1password
    kind: ClusterSecretStore
  target:
    name: example-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: example/username
    - secretKey: password
      remoteRef:
        key: example/password
```

## Verification commands

List all ExternalSecrets:

```bash
kubectl get externalsecret -A
```

Describe a failing ExternalSecret:

```bash
kubectl describe externalsecret <name> -n <namespace>
```

Check that the target Secret exists without printing secret values:

```bash
kubectl get secret <name> -n <namespace>
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | python3 -m json.tool
```

## Current ExternalSecrets

| ExternalSecret | Namespace | Target Secret | Purpose |
|----------------|-----------|---------------|---------|
| `tailscale-operator-oauth` | `tailscale` | `operator-oauth` | Tailscale Operator OAuth credentials |
| `grafana-oidc` | `monitoring` | `grafana-oidc` | Grafana Authentik OIDC client secret |
| `alertmanager-discord-webhook` | `monitoring` | `alertmanager-discord-webhook` | Alertmanager Discord receiver webhook |
| `velero-credentials` | `velero` | `velero-credentials` | MinIO/AWS/Azure backup credentials |

## Common failure modes

### `must be op:// format` or invalid key errors

Cause: wrong provider/key syntax.

Fix: use item/field format, for example `grafana/password`.

### `SecretSynced=False`

Check:

```bash
kubectl describe externalsecret <name> -n <namespace>
kubectl get clustersecretstore nqlabs-1password
```

Likely causes:

- wrong 1Password item name
- wrong field name
- service account token expired/revoked
- item not in the `NQLabs` vault

### ArgoCD shows false OutOfSync on ExternalSecret

ESO defaults fields such as `conversionStrategy`, `decodingStrategy`, and
`deletionPolicy`. ArgoCD has global diff customizations in `clusters/nqlabs-management/argocd/values.yaml`
so these should not create false OutOfSync anymore. If it reappears, verify `argocd-cm`
contains the global `resource.customizations.ignoreDifferences.external-secrets.io_ExternalSecret` entry.

## Future migration

Phase 2 may migrate the backend from 1Password to OpenBao. The desired application
manifests should stay mostly the same; the `ClusterSecretStore` backend changes.
