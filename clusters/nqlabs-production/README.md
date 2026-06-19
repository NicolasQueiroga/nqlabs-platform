# Cluster: nqlabs-production

Status: planned for desktop Proxmox multi-cluster rehearsal.

Purpose: production workload cluster. This is the production control-plane rehearsal,
not a fake namespace inside staging or management.

## Initial desktop VM allocation

| Field | Value |
|-------|-------|
| VMID | `133` |
| VM name | `talos-production-cp-01` |
| Node IP | `192.168.15.33/24` |
| Role | single-node control-plane+worker for first rehearsal |
| Sizing | 12 vCPU / 40GiB RAM / 48GiB thin disk |
| Bridge | `vmbr0` |
| Cluster endpoint | `https://192.168.15.33:6443` |

Service namespaces use the service name directly in this cluster, e.g.
`namespace/demo`, because staging/production separation is provided by separate
Kubernetes control planes.

Generated files belong in `clusters/nqlabs-production/generated/` and are ignored.
