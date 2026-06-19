# Cluster: nqlabs-staging

Status: planned for desktop Proxmox multi-cluster rehearsal.

Purpose: staging workload cluster. Platform operators deploy staging service instances
here through management ArgoCD.

## Initial desktop VM allocation

| Field | Value |
|-------|-------|
| VMID | `132` |
| VM name | `talos-staging-cp-01` |
| Node IP | `192.168.15.32/24` |
| Role | single-node control-plane+worker for first rehearsal |
| Sizing | 8 vCPU / 24GiB RAM / 32GiB thin disk |
| Bridge | `vmbr0` |
| Cluster endpoint | `https://192.168.15.32:6443` |

Service namespaces use the service name directly in this cluster, e.g.
`namespace/demo`, because the cluster boundary is the environment boundary.

Generated files belong in `clusters/nqlabs-staging/generated/` and are ignored.
