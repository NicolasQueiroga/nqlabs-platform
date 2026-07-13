# Runbook — Public `*.nqlabs.io` edge (Cloudflare Tunnel)

Private `*.nqlabs.network` is served over Tailscale (see
[cluster-and-edge-operations.md](cluster-and-edge-operations.md)). **Public**
`*.nqlabs.io` services need a real public edge. NQLabs uses **Cloudflare Tunnel**:
cloudflared dials out to Cloudflare, Cloudflare terminates public TLS, and matched
hostnames are forwarded over the tunnel to the cluster — no public IP, no inbound
ports.

This is **prerequisite-gated** and not active by default. The chart only renders a
public `*.io` HTTPRoute when `routes.public.enabled` (default off, requires review).

## One-time setup

1. **Create the tunnel** (Cloudflare dashboard → Zero Trust → Networks → Tunnels):
   - create a tunnel `nqlabs`, copy its **token**.
2. **Store the token** in OpenBao KV (NQLabs vault) as item `cloudflared-tunnel`,
   field `token`. (The ExternalSecret reads `cloudflared-tunnel/token`.)
3. **Public hostname registry**: update/review
   `infrastructure/networking/cloudflared/public-hostnames.md` first. This is the
   Git source of truth for the remotely-managed tunnel's hostname → origin rules.
4. **Public DNS** (`nqlabs.io` zone, Cloudflare): add the reviewed public hostnames
   as tunnel public hostnames (dashboard/API). Cloudflare creates the proxied
   CNAMEs. Do not point directly at pod IPs or bypass the production Gateway.
5. **Deploy cloudflared**: the `production-cloudflared` ArgoCD Application already
   targets `infrastructure/networking/cloudflared` on the production cluster
   (namespace `cloudflared`). It becomes Healthy once the token secret materializes.

## Exposure rules (enforced by the platform)

- public routes default **disabled**; enabling one is a reviewed platform PR.
- a public route must declare **explicit paths** (never publish `/admin`, `/metrics`, …).
- production public exposure requires explicit approval.
- a routine image bump must never add or change public exposure.
- Cloudflare dashboard/API hostname changes must mirror
  `infrastructure/networking/cloudflared/public-hostnames.md`.

## Verify

```bash
kubectl -n cloudflared get deploy cloudflared
kubectl -n cloudflared logs deploy/cloudflared | grep -i 'Registered tunnel connection'
curl -I https://<app>.nqlabs.io
```
