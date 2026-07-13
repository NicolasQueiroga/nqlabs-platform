# Runbook — Backup & DR (Velero)

Velero runs on **management, staging, and production**. Management has local Ceph RGW
plus offsite AWS/Azure. Staging/production use offsite AWS/Azure. Node-agent file
backup is enabled so local-path PV data is covered.

The `velero` namespace intentionally uses Pod Security Admission `privileged`.
This is scoped only to Velero because node-agent mounts kubelet host paths
(`/var/lib/kubelet/pods`, `/var/lib/kubelet/plugins`) to back up local-path PV
files. Do not relax service namespaces for this.

| BSL | Where | Use |
|-----|-------|-----|
| `local` (default) | in-cluster Ceph RGW | free, fast — routine pre-change snapshots |
| `aws` | AWS S3 `nqlabs-velero-backup` (us-east-1) | offsite DR |
| `azure` | Azure Blob `nqlabsvelero24612/velero` (Cool, LRS) | offsite DR |

Credentials: local RGW creds in `velero-rgw-credentials` (OBC-managed), offsite
creds in OpenBao KV (`velero-aws`, `velero-azure`) assembled into `velero-credentials`.

## Schedules

| Cluster | Schedule | Target | TTL | Purpose |
|---|---|---|---|---|
| management | `management-daily-local` daily 05:00 | Ceph RGW | 7d | cheap local rollback |
| management | `management-weekly-offsite-aws` Sundays 05:30 | AWS | 30d | offsite DR |
| staging/production | `cluster-daily-aws` daily 06:00 | AWS | 7d | workload DR |
| staging/production | `cluster-weekly-azure` Sundays 06:30 | Azure | 30d | second offsite copy |

## Take a backup (before risky changes)
```bash
kubectl -n velero exec deploy/velero -- \
  velero backup create pre-change-$(date +%F-%H%M) --wait            # -> local (default)

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

## Mandatory restore test

Unverified backups are not backups. Run this after changing Velero config and at
least monthly:

```bash
# 1. Create a small test namespace + PVC-backed pod.
kubectl create namespace velero-restore-test
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restore-test-data
  namespace: velero-restore-test
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 128Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: restore-test
  namespace: velero-restore-test
spec:
  restartPolicy: Never
  containers:
    - name: write-data
      image: docker.io/busybox:1.37.0
      command: ["sh", "-c", "echo nqlabs-restore-test > /data/proof.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          memory: 64Mi
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: restore-test-data
EOF

# 2. Back it up to the default location and wait.
kubectl -n velero exec deploy/velero -- \
  velero backup create restore-test-$(date +%F-%H%M) \
  --include-namespaces velero-restore-test \
  --default-volumes-to-fs-backup \
  --wait

# 3. Delete the namespace, then restore into the same name.
kubectl delete namespace velero-restore-test --wait=true
kubectl -n velero exec deploy/velero -- \
  velero restore create --from-backup <backup-name> --wait

# 4. Confirm objects and PVC data returned, then clean up.
kubectl get all,pvc -n velero-restore-test
kubectl delete namespace velero-restore-test
```

## Scope & follow-ups
- Velero backs up the cluster it runs on. Management backs up control-plane apps;
  staging/production back up service workloads and cluster-local state.
- PV data is file-backed through node-agent. CSI volume snapshots stay disabled
  until a snapshot-capable storage layer exists; local-path has no meaningful CSI
  snapshot backend.
- Cost control: short TTLs, AWS Standard, Azure Cool + LRS, and no premium redundancy.

## Cloud resources (provisioned via az/aws CLI)
- Azure: RG `nqlabs-backup` / SA `nqlabsvelero24612` / container `velero` (Standard_LRS, Cool)
- AWS: bucket `nqlabs-velero-backup` (us-east-1), IAM user `velero-nqlabs` (scoped S3 policy)
