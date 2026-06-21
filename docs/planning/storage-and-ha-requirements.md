# Requirements — Distributed storage (Rook/Ceph) & HA multi-node

Both are **hardware-gated** — they need disks and/or nodes the clusters don't have
yet. Captured so they can be scheduled.

## Rook/Ceph (distributed block + object storage)

**Why deferred:** clusters run **local-path** (node-bound). Ceph needs raw block
devices for OSDs; the Talos VMs have a single OS disk and no spare disks.

### Prerequisites
- **Spare raw disks** per OSD. Add virtual disks to the Talos VMs in Proxmox
  (`qm set <vmid> --scsiN local-lvm:<size>` — hotplug, no reboot), ≥3 OSD disks
  for replica-3. On a single node use `failureDomain: osd` (no node redundancy).
- True redundancy needs **multiple nodes** (see HA below); single-node Ceph gives
  storage *classes* (RBD/CephFS/RGW) but not node-failure tolerance.

### Install / deliver
- Chart: `rook-ceph` (operator) + `rook-ceph-cluster` (CephCluster, CephBlockPool,
  CephObjectStore). StorageClasses: `ceph-block` (RWO), `ceph-filesystem` (RWX),
  and an `ObjectStore` (S3) for Harbor/Velero.
- Then: Harbor on `ceph-block` + RGW; OpenBao Raft on `ceph-block`; Velero offsite
  can stay R2.

## HA multi-node clusters

**Why deferred:** each cluster is a **single control-plane VM** — no etcd quorum,
no node-failure tolerance.

### Prerequisites
- **3 control-plane nodes per cluster** for etcd quorum (NUC bare-metal expansion or
  additional Proxmox VMs), plus worker nodes for capacity.
- Talos: generate + apply controlplane configs for the new nodes, `talosctl bootstrap`
  stays single; join the additional CP nodes; verify etcd members = 3.
- Cilium/Gateway/LB-IPAM already multi-node ready; workloads get real anti-affinity.

### Order (also unblocks Harbor + OpenBao)
1. Add OSD disks → Rook/Ceph (storage classes).
2. Add nodes (NUCs) → etcd quorum + true HA.
3. Harbor (on Ceph), then OpenBao (Ceph + quorum), per
   [harbor-openbao-requirements.md](harbor-openbao-requirements.md).
