# IP Address Plan

> **Status:** Live three-cluster service factory (management/staging/production). Current architecture: [../docs/architecture/service-factory.md](../docs/architecture/service-factory.md). Single-cluster/desktop-lab references below are historical.


Status: active for the desktop fixed-IP lab. The desktop is the current
host for the full three-cluster architecture; NUCs later add/replace bare-metal
nodes in the same topology.

## Purpose

This document records the address ranges and fixed IP assignments currently used by
the NQLabs Platform. It exists to prevent accidental overlap as the platform moves
through its environments.

## Environment progression

NQLabs is intentionally moving through environments:

```text
Mac laptop / UTM lab
  → desktop fixed-IP full architecture (Ryzen 9 7950X, 124GB RAM, Proxmox/Talos VMs)
  → NUC bare-metal nodes added to the same clusters
```

The Mac laptop IPs are retained as historical Phase 0 context. The active platform
now runs on the desktop Proxmox host. The desktop plan is not blocked by NUCs: it
can run the full management/staging/production topology as Talos VMs. When NUCs
arrive, add them as nodes/capacity to the existing architecture and replace VM/LAN
assumptions with the final bare-metal VLAN/subnet plan only where needed.

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
Proxmox/KVM host for Talos VMs and the first full implementation of the topology.

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
Cilium LB pool:        192.168.15.192/28   (192-207)
CoreDNS LB IP:         192.168.15.192      (desktop-lab authoritative DNS)
platform Gateway LB:   192.168.15.193      (desktop-lab HTTPS Gateway)
Reserved LB:           192.168.15.194-207
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

This was the pre-Kubernetes bootstrap state. Current desktop-lab DNS uses the
Kubernetes CoreDNS Tailscale Service for split DNS, and CoreDNS returns the
Proxmox Tailscale IP `100.105.35.84` for platform/staging/production hostnames.
HAProxy on Proxmox then forwards HTTPS to the active cluster Gateway.

### Reserved desktop LoadBalancer assignments

| IP | Resource | Namespace | Purpose |
|----|----------|-----------|---------|
| `192.168.15.192` | CoreDNS LoadBalancer | `dns` | desktop-lab authoritative DNS |
| `192.168.15.193` | platform Gateway LoadBalancer | `platform` | desktop-lab HTTPS Gateway |
| `192.168.15.194-207` | planned/reserved | multi-cluster rehearsal | unique future Gateway/LB IPs |

Do not assign another service inside `192.168.15.192/28` without documenting it here.

### Talos VM IP plan

| IP | VM | Cluster | Role |
|----|----|---------|------|
| `192.168.15.30` | `talos-desktop-cp-01` / VMID `130` / MAC `BC:24:11:15:00:30` | `nqlabs-desktop-lab` | large all-in-one bootstrap node; 16 vCPU, 64GB RAM, 96GB thin disk |
| `192.168.15.31` | `talos-management-cp-01` / VMID `131` / MAC `BC:24:11:15:00:31` | `nqlabs-management` | initial single-node management cluster; 8 vCPU, 32GB RAM, 48GB thin disk |
| `192.168.15.32` | `talos-staging-cp-01` / VMID `132` | `nqlabs-staging` | initial single-node staging cluster; 8 vCPU, 24GB RAM, 32GB thin disk |
| `192.168.15.33` | `talos-production-cp-01` / VMID `133` | `nqlabs-production` | initial single-node production cluster; 12 vCPU, 40GB RAM, 48GB thin disk |
| `192.168.15.34-39` | TBD | desktop multi-cluster expansion | additional control-plane/worker VMs |

The management/staging/production VM sizes are the max recommended CPU/RAM profile for the current desktop before repurposing the 1.9TB SSD: 28 vCPU / 96GB RAM / 128GB thin disk declared across the three clusters. Keep VM 130 as a temporary substrate proof, not a permanent fourth large cluster, unless RAM/storage pressure is explicitly reviewed.

Wake-on-LAN for the desktop host:

```bash
wakeonlan 74:56:3c:f7:32:39
```

BIOS must also be configured with AC power recovery enabled so the host powers back
on after an outage.


### Planned desktop multi-cluster LoadBalancer assignments

The current HAProxy edge binds only to Proxmox `tailscale0` (`100.105.35.84`). In
the three-cluster rehearsal, keep this Tailscale-only edge and route by TLS SNI to
unique Gateway IPs per cluster:

| IP | Planned owner | Purpose |
|----|---------------|---------|
| `192.168.15.194` | `nqlabs-management` CoreDNS | future authoritative DNS if/when management replaces desktop-lab DNS |
| `192.168.15.195` | `nqlabs-management` Gateway | `*.platform.nqlabs.network` |
| `192.168.15.196` | `nqlabs-staging` Gateway | `*.staging.nqlabs.network` |
| `192.168.15.197` | `nqlabs-production` Gateway | `*.production.nqlabs.network` |
| `192.168.15.198-207` | reserved | future LB services / expansion |

Do not let two clusters announce the same LoadBalancer IP on the LAN. Each cluster
needs its own Cilium LB IPAM pool or explicitly reserved IP range.

## NUC node expansion planning placeholder

NUCs should be planned as nodes/capacity for the existing architecture, not as a
separate platform capability phase. Before bare-metal installation, define how each
NUC joins one of the three existing clusters:

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
- target cluster for each NUC
- whether the NUC adds capacity or replaces a Proxmox VM node

The Phase 0 `192.168.64.0/24` UTM range should not be carried into the desktop or
NUC environments as-is unless explicitly chosen and documented. It is a Mac laptop
lab implementation detail, not the durable production network.
