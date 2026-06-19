# Clusters

This directory contains per-cluster bootstrap intent for the NQLabs Platform.

Generated Talos secrets, machine configs, kubeconfigs, and talosconfigs are ignored
and must not be committed. Store generated secrets in 1Password and generated access
files under `clusters/<cluster>/generated/` on the operator workstation.

## Current and target clusters

| Cluster | Status | Purpose |
|---------|--------|---------|
| `desktop-lab` | active | single-cluster desktop substrate validation |
| `nqlabs-management` | planned on desktop Proxmox | management/platform control services |
| `nqlabs-staging` | planned on desktop Proxmox | staging workloads |
| `nqlabs-production` | planned on desktop Proxmox | production workloads |
| `lab` | legacy Mac/UTM | original Phase 0 laptop lab reference |

The desktop is expected to run the full three-cluster topology as VMs before that
same model is moved to NUC bare metal later.

## Folder contract

Each real cluster should have:

```text
clusters/<cluster>/
├── README.md
├── patches/
└── generated/   # gitignored
```

`patches/` may contain safe, non-secret Talos config patches. `generated/` contains
machine configs, secrets, talosconfig, and kubeconfig created by `talosctl`.

Lifecycle procedure: [`docs/runbooks/cluster-lifecycle.md`](../docs/runbooks/cluster-lifecycle.md)
