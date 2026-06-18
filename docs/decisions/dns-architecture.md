# Decision: DNS Architecture

## Status

Accepted — Phase 0 implemented.

## Context

NQLabs needs internal service discovery that works from any trusted device while keeping
platform services private by default. The platform also needs a clean split between:

- private/internal services under `nqlabs.network`
- future public services under `nqlabs.io`

`nqlabs.network` is owned by NQLabs and delegated in Cloudflare, but it is used as
the private/platform/server domain. Service records are resolved through the private
access layer, not published as public application A records.

`nqlabs.io` is the public/user-facing domain. Its DNS is managed by Cloudflare, but
application exposure on `.io` is deferred until the desktop/NUC public-edge phase.

## Decision

Use Tailscale split DNS plus an in-cluster authoritative DNS stack for private names:

```text
Tailnet client
    ↓ query *.nqlabs.network
Tailscale split DNS
    ↓ nameserver 100.125.207.63
CoreDNS (standalone, dns namespace)
    ↓ reads records
etcd DNS backend
    ↑ records written by
external-dns watching Gateway API HTTPRoutes
```

Private internal naming:

| Pattern | Purpose | Example |
|---------|---------|---------|
| `<service>.platform.nqlabs.network` | Singleton platform tools | `argocd.platform.nqlabs.network` |
| `<service>.staging.nqlabs.network` | Staging application services | `api.staging.nqlabs.network` |
| `<service>.production.nqlabs.network` | Production application services in the private platform network | `api.production.nqlabs.network` |

Use `production` in full. Do not use `prod`.

## Implemented components

| Component | Current value |
|-----------|---------------|
| Standalone CoreDNS namespace | `dns` |
| CoreDNS LoadBalancer IP | `192.168.64.192` |
| CoreDNS Tailscale IP | `100.125.207.63` |
| etcd backend service | ClusterIP `10.103.246.202` |
| external-dns provider | CoreDNS/etcd |
| Tailscale split DNS | `nqlabs.network` → `100.125.207.63` |
| Gateway IP | `192.168.64.193` |

## TLS model

Private `nqlabs.network` services use publicly trusted Let's Encrypt certificates through Cloudflare DNS-01. The services remain private/Tailscale-only; DNS-01 only proves domain ownership through temporary TXT records.

Current wildcard cert SANs:

- `*.platform.nqlabs.network`
- `*.staging.nqlabs.network`
- `*.production.nqlabs.network`

The NQLabs Internal CA remains available for future purely internal bootstrap use. Public/user-facing `.io` endpoints are deferred until the desktop/NUC public-edge phase.

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
dig @192.168.64.192 argocd.platform.nqlabs.network +short
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
