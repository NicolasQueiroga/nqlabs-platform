# Runbook — Backup & DR (Velero)

Velero runs on the **management** cluster, **on-demand only** (no schedule, no
node-agent) with three backup storage locations:

| BSL | Where | Use |
|-----|-------|-----|
| `minio` (default) | in-cluster MinIO (local-path) | free, fast — routine pre-change snapshots |
| `aws` | AWS S3 `nqlabs-velero-backup` (us-east-1) | offsite DR |
| `azure` | Azure Blob `nqlabsvelero24612/velero` (Cool, LRS) | offsite DR |

Credentials live in 1Password (`velero-minio`, `velero-aws`, `velero-azure`) and are
assembled into the `velero-credentials` secret by External Secrets.

## Take a backup (before risky changes)
```bash
kubectl -n velero exec deploy/velero -- \
  velero backup create pre-change-$(date +%F-%H%M) --wait            # -> minio (default)

# offsite copy:
... velero backup create dr-$(date +%F) --storage-location aws  --wait
... velero backup create dr-$(date +%F) --storage-location azure --wait
```
Velero `ttl` (default 30 days) auto-prunes old backups from the store.

## List / inspect / restore
```bash
kubectl -n velero exec deploy/velero -- velero backup get
kubectl -n velero exec deploy/velero -- velero backup describe <name> --details
kubectl -n velero exec deploy/velero -- velero restore create --from-backup <name>
```

## Scope & follow-ups
- Velero backs up the cluster it runs on = **management** (ArgoCD apps, configs,
  secrets metadata, CRs — git re-creates the rest on restore).
- For **staging/production** workload DR, deploy Velero on those clusters too (same
  pattern as Kyverno/Falco replication). PV *data* needs `deployNodeAgent: true`.
- Cost control: no schedule (manual only), Azure Cool + LRS, S3 Standard, `ttl` prune.

## Cloud resources (provisioned via az/aws CLI)
- Azure: RG `nqlabs-backup` / SA `nqlabsvelero24612` / container `velero` (Standard_LRS, Cool)
- AWS: bucket `nqlabs-velero-backup` (us-east-1), IAM user `velero-nqlabs` (scoped S3 policy)
