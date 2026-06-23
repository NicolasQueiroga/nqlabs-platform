# Runbook — Cluster access, recovery, and the Tailscale/HAProxy edge

Operational reference for the Proxmox-hosted NQLabs clusters and how the platform
is reached over Tailscale.

---

## Topology

The three clusters are Talos VMs on the Proxmox host `nqlabs-desktop`
(Tailscale `100.105.35.84`):

| Cluster | VM | API server | Gateway LB IP |
|---|---|---:|---:|
| management | 131 | `https://192.168.15.31:6443` | `192.168.15.195` |
| staging | 132 | `https://192.168.15.32:6443` | `192.168.15.196` |
| production | 133 | `https://192.168.15.33:6443` | `192.168.15.198` |

Management ArgoCD deploys to staging/production by cluster **name**
(`nqlabs-staging`, `nqlabs-production`) — see
[remote-cluster-service-factory.md](remote-cluster-service-factory.md).

---

## Reaching the clusters

The cluster APIs are not directly routable from a laptop unless the Tailscale
subnet route `192.168.15.0/24` is accepted. Two options:

### A. SSH tunnels through the Proxmox host (always works)

```bash
ssh -fN -L 31443:192.168.15.31:6443 root@100.105.35.84   # management
ssh -fN -L 16443:192.168.15.32:6443 root@100.105.35.84   # staging
ssh -fN -L 26443:192.168.15.33:6443 root@100.105.35.84   # production
```

The `/tmp/{management,staging,prod}-kubeconfig-tunnel` kubeconfigs point at
`127.0.0.1:{31443,16443,26443}` respectively. Tunnels die when the SSH process
exits — re-establish them as above.

### B. Tailscale subnet route (direct `192.168.15.x`)

The `nqlabs-lab-router` Connector advertises `192.168.15.0/24`. The route must be
**enabled** in the tailnet and the client must **accept subnets**. Enable the route
via the Tailscale API (see below) and toggle "use subnets" on the client.

---

## Edge: how `*.nqlabs.network` is served

```
client → Tailscale split DNS (*.nqlabs.network → coredns device 100.120.180.x)
       → name resolves to 100.105.35.84 (nqlabs-desktop)
       → HAProxy on :443 (SNI passthrough) routes by suffix:
            *.platform.nqlabs.network   → management gateway 192.168.15.195:443
            *.staging.nqlabs.network    → staging gateway    192.168.15.196:443
            *.production.nqlabs.network → production gateway  192.168.15.198:443
       → Cilium Gateway terminates TLS (wildcard cert) and routes to the Service
Proxmox UI: https://proxmox.platform.nqlabs.network:8006 → pveproxy directly on the host.
```

- Tailscale operator + CoreDNS split DNS + the subnet-router Connector are GitOps-managed:
  `clusters/nqlabs-management/argocd/apps/tailscale-operator.yaml` and `tailscale-config.yaml`,
  values in `infrastructure/networking/tailscale/`.
- Tailnet ACL/tag intent is stored in
  `infrastructure/networking/tailscale/tailnet-policy.hujson`. Review and apply it
  through Tailscale Admin → Access Controls or the tailnet policy API. Do **not**
  let cluster GitOps mutate global tailnet ACLs automatically.
- HAProxy config lives on the desktop at `/etc/haproxy/haproxy.cfg` (not in git). After
  editing: `haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy`.

---

## Tailscale API (no separate user key required)

The Tailscale operator's OAuth client can drive the tailnet API:

```bash
CID=$(kubectl -n tailscale get secret operator-oauth -o jsonpath='{.data.client_id}' | base64 -d)
CSEC=$(kubectl -n tailscale get secret operator-oauth -o jsonpath='{.data.client_secret}' | base64 -d)
TOK=$(curl -s -d "client_id=$CID" -d "client_secret=$CSEC" https://api.tailscale.com/api/v2/oauth/token | yq -r .access_token)
```

Useful operations:

```bash
# Split DNS (per-domain resolver — low blast radius)
curl -s -H "Authorization: Bearer $TOK" https://api.tailscale.com/api/v2/tailnet/-/dns/split-dns
curl -s -X PATCH -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"nqlabs.network":["<coredns-device-ip>"]}' https://api.tailscale.com/api/v2/tailnet/-/dns/split-dns

# Remove a stale device / approve a subnet route
curl -s -X DELETE -H "Authorization: Bearer $TOK" https://api.tailscale.com/api/v2/device/<id>
curl -s -X POST   -H "Authorization: Bearer $TOK" -d '{"routes":["192.168.15.0/24"]}' \
  https://api.tailscale.com/api/v2/device/<router-id>/routes
```

> If a CoreDNS device is recreated it gets a new Tailscale IP — repoint the
> `nqlabs.network` split-DNS to the new IP or names stop resolving.

---

## Recovery playbooks

### Staging/production cluster API down (`sync=Unknown` on every remote app)

Symptom: all apps targeting a cluster show `sync=Unknown`; the API port is closed.
Cause (seen after a Proxmox host restart): the Talos VM booted the **install ISO**
(`boot: order=ide2`) instead of the installed disk.

```bash
ssh root@100.105.35.84 'qm config <vmid> | grep ^boot'        # shows order=ide2
ssh root@100.105.35.84 'qm set <vmid> --boot order=scsi0'     # boot from disk
ssh root@100.105.35.84 'qm stop <vmid>; sleep 3; qm start <vmid>'
# API returns in ~60s; management VM 131 is the reference (boots scsi0).
```

### ArgoCD `ComparisonError: unable to resolve parseableType ...`

After a remote cluster API restart, apps may error on diff even though resources
applied (`lastOp: Succeeded`) and the CRDs/OpenAPI are fine on the cluster. This is
a stale per-cluster OpenAPI cache in the application-controller.

```bash
# Confirm the cluster is actually fine, e.g. kubectl explain certificate.spec works there, then:
kubectl -n argocd rollout restart statefulset argocd-application-controller
```

Restart **after** the remote cluster's OpenAPI is stable (a restart that races
publication re-caches stale schema — restart again once stable).

### Verify overall health

```bash
kubectl -n argocd get applications \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```
