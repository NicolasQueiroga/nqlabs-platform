# Cluster: desktop-lab

Status: active desktop substrate validation cluster.

Purpose: prove Proxmox + Talos + Cilium + GitOps + DNS + TLS + monitoring on the
fixed-IP desktop before moving to the full three-cluster rehearsal.

| Field | Value |
|-------|-------|
| Proxmox host | `nqlabs-desktop` / `192.168.15.20` / Tailscale `100.105.35.84` |
| VMID | `130` |
| VM name | `talos-desktop-cp-01` |
| Node IP | `192.168.15.30/24` |
| Role | single-node control-plane+worker |
| Sizing | 16 vCPU / 64GiB RAM / 96GiB thin disk |
| NIC | `ens18` inside Talos VM |
| Cluster endpoint | `https://192.168.15.30:6443` |
| Cilium LB pool | `192.168.15.192/28` |
| CoreDNS LB | `192.168.15.192` |
| Gateway LB | `192.168.15.193` |
| External HTTPS edge | Proxmox HAProxy on `100.105.35.84:443` TCP passthrough to Gateway |

All generated files stay under `clusters/desktop-lab/generated/` and are ignored.

This cluster is not the final topology. It is the boring substrate proof before
creating:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```
