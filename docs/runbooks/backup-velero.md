# Runbook — Backup & DR (Velero)

Velero backs up cluster resources (and PV data via the node-agent/Kopia) to an
S3 target. Default target = in-cluster **MinIO** on the management cluster
(`infrastructure/storage/minio`). Daily schedule at 03:00, 7-day retention.

> MinIO is a *backup target*, not durable storage. For real offsite DR, point the
> backup storage location at **Cloudflare R2** (below).

## Activate
1. Add a 1Password (NQLabs vault) item **`velero-backup`** with fields:
   - `access-key` — any value (becomes the MinIO root user + S3 access key)
   - `secret-key` — any value (MinIO root password + S3 secret key)
2. Ping the agent to wire the `management-minio` + `management-velero` apps (held
   until creds exist so health stays clean).
3. Verify:
   ```bash
   velero backup-location get        # default = Available
   velero backup create test-1 --wait
   velero backup get
   ```

## Restore test
```bash
velero restore create --from-backup test-1 --include-namespaces demo
velero restore get
```

## Offsite upgrade — Cloudflare R2
1. Cloudflare → R2 → create bucket `nqlabs-velero` + an R2 API token (S3 access key/secret).
2. Store the keys in 1Password `velero-backup` (reuse `access-key`/`secret-key`).
3. In `infrastructure/backup/velero/values.yaml` set the backupStorageLocation:
   - `bucket: nqlabs-velero`
   - `config.s3Url: https://<account-id>.r2.cloudflarestorage.com`
   - `config.region: auto`, add `config.checksumAlgorithm: ""` (R2 quirk)
4. Drop the MinIO app. Now backups are offsite (survive a full Proxmox loss).
