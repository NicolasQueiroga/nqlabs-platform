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
  → desktop fixed-IP lab (Ryzen 9 7950X, 128GB RAM, 2TB SSD)
  → NUC bare-metal private cloud (`nqlabs-management`, `nqlabs-staging`, `nqlabs-production`)
```

The current IPs are valid for the Mac laptop test environment only. They prove the
architecture, but they are not the final production addressing plan.

When the platform moves to the desktop, add a new section with the desktop host IP,
desktop VM/runtime subnet, LoadBalancer pool, Tailscale routes, and DNS records.
When the platform moves to NUCs, replace lab assumptions with the final VLAN/subnet
plan.

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

## Desktop fixed-IP lab placeholder

Before moving the lab from the Mac to the desktop, document:

- desktop fixed IP
- VM/runtime networking model on the desktop
- Kubernetes node IPs
- Cilium LoadBalancer pool
- platform Gateway IP
- DNS names and Tailscale routes
- any firewall/router changes
- whether the desktop lab will run one Talos VM cluster first or rehearse the full
  three-cluster topology (`nqlabs-management`, `nqlabs-staging`, `nqlabs-production`)

The desktop environment should be treated as an intermediate durability test: more
stable than the Mac laptop, but still not the final NUC cloud.

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
