# IP Address Plan

Status: active for Phase 0 Mac laptop lab; must be revised for the fixed-IP
desktop lab and expanded again for the NUC cloud.

## Purpose

This document records the address ranges and fixed IP assignments currently used by
the NQLabs Platform. It exists to prevent accidental overlap as the platform moves
through its environments.

## Environment progression

NQLabs is intentionally moving through environments:

```text
Mac laptop / UTM lab
  → desktop fixed-IP virtualized NUC rehearsal (Ryzen 9 7950X, 124GB RAM, 130GB active VM thin pool)
  → NUC bare-metal implementation (`nqlabs-management`, `nqlabs-staging`, `nqlabs-production`)
```

The current IPs are valid for the Mac laptop test environment only. They prove the
architecture, but they are not the final production addressing plan.

When the platform moves to the desktop, use
`docs/runbooks/desktop-lab-bootstrap.md` and add a filled desktop section with the
desktop host IP, desktop VM/runtime subnet, LoadBalancer pool, Tailscale routes,
and DNS records.
When the platform moves to NUCs, preserve the desktop-rehearsed cluster topology but
replace VM/LAN assumptions with the final bare-metal VLAN/subnet plan.

## Phase 0 Mac laptop network model

The current Phase 0 cluster runs in UTM using Shared Network/NAT on Nick's Mac.

```text
Mac / UTM host
  └── UTM Shared Network: 192.168.64.0/24
        └── Talos VM / Kubernetes node
              └── Cilium LoadBalancer IPs
```

Tailscale provides remote/private access to the same internal service names.

## Current ranges

| Range / Address | Owner | Purpose | Notes |
|-----------------|-------|---------|-------|
| `192.168.64.0/24` | UTM Shared Network | Phase 0 VM/LB network | Mac laptop-local NAT network |
| `192.168.64.192/28` | Cilium LB IPAM | Kubernetes LoadBalancer pool | Announced with Cilium L2 on `enp0s1` |
| `192.168.64.192` | standalone CoreDNS Service | Authoritative DNS for `nqlabs.network` | Also exposed through Tailscale |
| `192.168.64.193` | platform Gateway Service | HTTPS entrypoint for platform/staging/production routes | All current wildcard-hosted services terminate here |
| `100.125.207.63` | Tailscale | Tailnet IP for CoreDNS/split DNS path | Tailscale admin console points `nqlabs.network` here |

## Current DNS-to-IP flow

For a platform URL such as:

```text
argocd.platform.nqlabs.network
```

resolution flow is:

```text
client
  → Tailscale split DNS for nqlabs.network
  → CoreDNS at 100.125.207.63
  → external-dns-managed record
  → 192.168.64.193 platform Gateway
```

For a service URL such as:

```text
demo.staging.nqlabs.network
```

traffic flow is:

```text
client
  → DNS result 192.168.64.193
  → Cilium Gateway / Envoy
  → HTTPRoute
  → Service
  → Pod
```

## Reserved Phase 0 LoadBalancer assignments

| IP | Resource | Namespace | Purpose |
|----|----------|-----------|---------|
| `192.168.64.192` | CoreDNS LoadBalancer | `dns` | authoritative internal DNS |
| `192.168.64.193` | platform Gateway LoadBalancer | `platform` | HTTPS Gateway for platform/services |
| `192.168.64.194-207` | unassigned | n/a | reserved for future Phase 0 LB services |

Do not assign another service inside `192.168.64.192/28` without documenting it here.

## Kubernetes-internal addresses

ClusterIP addresses such as the following are Kubernetes-internal and may change if
resources are recreated:

```text
CoreDNS ClusterIP: 10.103.246.202
```

Do not build external dependencies on ClusterIP addresses. Use Services/DNS names
inside the cluster and LoadBalancer/Gateway addresses outside the cluster.

## Desktop fixed-IP lab — active

The Mac remains the development/control workstation. The desktop is the stable
Proxmox/KVM host for Talos VMs and the virtualized rehearsal of the NUC topology.

Host: `nqlabs-desktop`
Hardware: AMD Ryzen 9 7950X, 32 threads, 124GB RAM
Active Proxmox VM storage: 130.3GB `local-lvm` thin pool on 223.6GB Force MP510 SSD
Secondary disk: 1.9TB Predator GM7000 SSD, currently NTFS and not assigned to Proxmox
Proxmox: VE 9.2.2
Ethernet: `nic0` bridged into `vmbr0`
Ethernet MAC: `74:56:3c:f7:32:39`
Tailscale: `100.105.35.84`

```text
Proxmox host:          192.168.15.20   (fixed)
LAN subnet:            192.168.15.0/24
Gateway:               192.168.15.1
Talos VM range:        192.168.15.30-49
Cilium LB pool:        192.168.15.200/28   (200-215)
CoreDNS LB IP:         192.168.15.200      (future cluster split DNS backend)
platform Gateway LB:   192.168.15.201      (HTTPS entry point)
Reserved LB:           192.168.15.202-215
```

### Temporary Proxmox DNS before Kubernetes CoreDNS

Until the desktop Kubernetes cluster exists, Proxmox itself runs a temporary CoreDNS
service for the desktop management hostname:

```text
proxmox.platform.nqlabs.network → 100.105.35.84
```

Tailscale split DNS currently routes:

```text
nqlabs.network → 100.105.35.84
```

This is temporary. After the desktop cluster creates the Kubernetes CoreDNS
Tailscale Service, update Tailscale split DNS from `100.105.35.84` to the new
CoreDNS Tailscale IP.

### Reserved desktop LoadBalancer assignments

| IP | Resource | Namespace | Purpose |
|----|----------|-----------|---------|
| `192.168.15.200` | CoreDNS LoadBalancer | `dns` | authoritative DNS / future Tailscale split DNS target |
| `192.168.15.201` | platform Gateway LoadBalancer | `platform` | HTTPS Gateway |
| `192.168.15.202-215` | unassigned | n/a | reserved for future LB services |

Do not assign another service inside `192.168.15.200/28` without documenting it here.

### Talos VM IP plan

| IP | VM | Cluster | Role |
|----|----|---------|------|
| `192.168.15.30` | `talos-desktop-cp-01` / VMID `130` / MAC `BC:24:11:15:00:30` | `nqlabs-desktop-lab` | large all-in-one bootstrap node; 16 vCPU, 64GB RAM, 96GB thin disk |
| `192.168.15.31-39` | TBD | desktop multi-cluster rehearsal | management / staging / production VMs |

Wake-on-LAN for the desktop host:

```bash
wakeonlan 74:56:3c:f7:32:39
```

BIOS must also be configured with AC power recovery enabled so the host powers back
on after an outage.

## Phase 1 NUC planning placeholder

Phase 1 must define a separate address plan before bare-metal installation. The
target is three Kubernetes clusters, not one large cluster:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```

Required decisions:

- management network
- Talos API/control-plane network
- Kubernetes node subnet
- LoadBalancer/service subnet
- storage network, if separated
- Tailscale subnet routes
- DHCP reservations or static IP assignments
- DNS names for each node

The Phase 0 `192.168.64.0/24` UTM range should not be carried into the desktop or
NUC environments as-is unless explicitly chosen and documented. It is a Mac laptop
lab implementation detail, not the durable production network.
