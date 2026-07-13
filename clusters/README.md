# Clusters

This directory contains per-cluster bootstrap intent for the NQLabs Platform.

Generated Talos secrets, machine configs, kubeconfigs, and talosconfigs are ignored
and must not be committed. Store generated secrets in OpenBao and generated access
files under `clusters/<cluster>/generated/` on the operator workstation.

## Clusters (live)

| Cluster | VM / IP | Purpose |
|---------|---------|---------|
| `nqlabs-management` | VM131 `192.168.15.31` | ArgoCD app-of-apps + service factory |
| `nqlabs-staging` | VM132 `192.168.15.32` | staging workloads (+ previews) |
| `nqlabs-production` | VM133 `192.168.15.33` | production workloads |

The three-cluster topology runs as Talos VMs on the Proxmox desktop. The earlier
single-node labs (Mac/UTM `lab` and the desktop-lab VM 130) are retired. NUCs later
add bare-metal nodes/capacity to this same model.

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
