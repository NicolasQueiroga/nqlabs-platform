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
2. **Store the token** in 1Password (NQLabs vault) as item `cloudflared-tunnel`,
   field `token`. (The ExternalSecret reads `cloudflared-tunnel/token`.)
3. **Public DNS** (`nqlabs.io` zone, Cloudflare): add the public hostnames as
   tunnel public hostnames (dashboard), e.g. `checkout.nqlabs.io` → service
   `http://<cluster-gateway-or-service>`. Cloudflare creates the proxied CNAMEs.
4. **Deploy cloudflared**: add an ArgoCD Application for
   `infrastructure/networking/cloudflared` to the management app-of-apps targeting
   the cluster that hosts the public services (namespace `cloudflared`,
   `CreateNamespace=true`). It becomes Healthy once the token secret materializes.

## Exposure rules (enforced by the platform)

- public routes default **disabled**; enabling one is a reviewed platform PR.
- a public route must declare **explicit paths** (never publish `/admin`, `/metrics`, …).
- production public exposure requires explicit approval.
- a routine image bump must never add or change public exposure.

## Verify

```bash
kubectl -n cloudflared get deploy cloudflared
kubectl -n cloudflared logs deploy/cloudflared | grep -i 'Registered tunnel connection'
curl -I https://<app>.nqlabs.io
```
