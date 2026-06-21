# Decision: DNS Architecture

> **Status:** Live three-cluster service factory (management/staging/production). Current architecture: [../docs/architecture/service-factory.md](../docs/architecture/service-factory.md). Single-cluster/desktop-lab references below are historical.


## Status

Accepted — active on desktop-lab; multi-cluster desktop fanout planned.

## Context

NQLabs needs internal service discovery that works from any trusted device while keeping
platform services private by default. The platform also needs a clean split between:

- private/internal services under `nqlabs.network`
- future public services under `nqlabs.io`

`nqlabs.network` is owned by NQLabs and delegated in Cloudflare, but it is used as
the private/platform/server domain. Service records are resolved through the private
access layer, not published as public application A records.

`nqlabs.io` is the public/user-facing domain. Its DNS is managed by Cloudflare, but
application exposure on `.io` is deferred until the deliberate public-edge design, which can be rehearsed on desktop before NUCs.

## Decision

Use Tailscale split DNS plus an in-cluster authoritative DNS stack for private names:

```text
Tailnet client
    ↓ query *.nqlabs.network
Tailscale split DNS
    ↓ nameserver: Kubernetes CoreDNS Tailscale IP
CoreDNS (standalone, dns namespace)
    ↓ answers platform/staging/production with Proxmox tailscale0 IP
Proxmox HAProxy (100.105.35.84:80/443)
    ↓ TCP passthrough / future SNI fanout
Cilium Gateway API in the target cluster
```

Private internal naming:

| Pattern | Purpose | Example |
|---------|---------|---------|
| `<service>.platform.nqlabs.network` | Singleton platform tools | `argocd.platform.nqlabs.network` |
| `<service>.staging.nqlabs.network` | Staging application services | `api.staging.nqlabs.network` |
| `<service>.production.nqlabs.network` | Production application services in the private platform network | `api.production.nqlabs.network` |

Use `production` in full. Do not use `prod`.

## Implemented components

| Component | Desktop-lab value |
|-----------|-------------------|
| Standalone CoreDNS namespace | `dns` |
| CoreDNS LoadBalancer IP | `192.168.15.192` |
| CoreDNS Tailscale IP | `100.114.154.64` |
| etcd backend service | ClusterIP `10.105.253.211` |
| external-dns provider | CoreDNS/etcd |
| Tailscale split DNS | `nqlabs.network` → `100.114.154.64` |
| Proxmox Tailscale edge | `100.105.35.84` |
| Desktop-lab Gateway IP | `192.168.15.193` |

## TLS model

Private `nqlabs.network` services use publicly trusted Let's Encrypt certificates through Cloudflare DNS-01. The services remain private/Tailscale-only; DNS-01 only proves domain ownership through temporary TXT records.

Current wildcard cert SANs:

- `*.platform.nqlabs.network`
- `*.staging.nqlabs.network`
- `*.production.nqlabs.network`

The NQLabs Internal CA remains available for future purely internal bootstrap use. Public/user-facing `.io` endpoints are deferred until the deliberate public-edge design, which can be rehearsed on desktop before NUCs.

## Why not `*.lab.nqlabs.network`?

The original Phase 0 naming used `argocd.platform.lab.nqlabs.network`. That was removed
because platform tools are singletons. There is not a staging Grafana and a production
Grafana; Grafana selects data sources/dashboards for different environments.

The environment belongs to application service names, not singleton platform tools.

## Operational commands

Check DNS through normal resolver path:

```bash
dig argocd.platform.nqlabs.network +short
```

Check CoreDNS directly:

```bash
dig @100.114.154.64 argocd.platform.nqlabs.network +short
```

Check Gateway and routes:

```bash
kubectl get gateway -n platform
kubectl get httproute -A
```

Check external-dns:

```bash
kubectl logs -n dns deployment/external-dns --tail=50
```


## Desktop multi-cluster DNS / ingress target

During the three-cluster desktop rehearsal, keep one private Tailscale DNS answer for
user-facing hostnames:

```text
*.platform.nqlabs.network    -> 100.105.35.84
*.staging.nqlabs.network     -> 100.105.35.84
*.production.nqlabs.network  -> 100.105.35.84
```

Then use HAProxy on Proxmox to route by TLS SNI:

| Hostname pattern | Target cluster |
|------------------|----------------|
| `*.platform.nqlabs.network` | `nqlabs-management` |
| `*.staging.nqlabs.network` | `nqlabs-staging` |
| `*.production.nqlabs.network` | `nqlabs-production` |

This preserves a single Tailscale-only edge while separating environments by
Kubernetes control plane.

## Consequences

Positive:

- No per-device `/etc/hosts` management.
- Internal services remain private by default.
- Gateway API hostnames automatically become DNS records through external-dns.
- Naming separates platform tools from staging/production workloads.

Tradeoffs:

- Tailnet DNS must remain configured correctly.
- CoreDNS/etcd becomes part of the private access path.
- Public `.io` service exposure is intentionally deferred until a real public edge
  exists for the desktop/NUC phases.
