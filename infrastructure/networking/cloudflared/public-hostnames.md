# Cloudflare Tunnel public hostname registry

This file is the Git-reviewed registry for remotely-managed Cloudflare Tunnel
ingress rules. The active tunnel is token/remote-managed, so Cloudflare stores the
actual hostname → origin rules in Zero Trust. Keep this file and the dashboard in
lockstep; production public exposure changes require a platform PR before the
dashboard/API change.

## Desired rules

| Hostname | Origin | Status | Notes |
|---|---|---|---|
| `*.nqlabs.io` | `https://192.168.15.198` | planned | Production public edge wildcard to production Cilium Gateway. Use only after Gateway wildcard cert / public-route review is complete. |

## Apply checklist

1. Review platform PR changing this registry and any `routes.public.*` values.
2. In Cloudflare Zero Trust → Networks → Tunnels → `nqlabs`, add/update matching
   Public Hostname entries.
3. Origin should point at the approved production edge only; do not point directly
   to pod or service IPs.
4. Verify with `curl -I https://<host>.nqlabs.io` and Gatus/blackbox probes.
5. Never change dashboard rules as part of a routine image-tag release.

