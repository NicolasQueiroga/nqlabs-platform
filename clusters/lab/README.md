# Cluster: lab

Local development cluster running on a single UTM VM (MacBook Pro M1).

| Property | Value |
|----------|-------|
| Purpose | Phase 0 — platform stack validation |
| Architecture | ARM64 (Apple M1 Pro) |
| Nodes | 1 (control-plane + worker) |
| Talos version | v1.13.3 |
| Network | UTM Shared Network (NAT), `192.168.64.0/24` |
| Access | Tailscale split DNS + Cilium Gateway API |

## Current platform endpoints

| Service | URL |
|---------|-----|
| ArgoCD | `https://argocd.platform.nqlabs.network` |
| Grafana | `https://grafana.platform.nqlabs.network` |
| Prometheus | `https://prometheus.platform.nqlabs.network` |
| Alertmanager | `https://alertmanager.platform.nqlabs.network` |

All are private internal services under `nqlabs.network` and resolve through
Tailscale split DNS to the in-cluster CoreDNS/external-dns stack.

## Directory structure

```
clusters/lab/
├── patches/
│   └── controlplane.yaml   # Allows workloads on control plane (single-node only)
└── generated/              # gitignored — machine configs and talosconfig live here
```

## Bootstrap

See [docs/runbooks/talos-bootstrap-laptop.md](../../docs/runbooks/talos-bootstrap-laptop.md)

## Notes

- The `generated/` directory is gitignored. Never commit files from it.
- Cluster secrets are stored in 1Password under `NQLabs / talos-lab-secrets`.
- This cluster is for development only — not production.
