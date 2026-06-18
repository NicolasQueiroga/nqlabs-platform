# Cluster Topology

Status: target architecture selected.

## Decision

NQLabs targets a three-cluster model:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```

The Mac laptop lab remains a single-cluster approximation. The fixed-IP desktop lab
should rehearse the three-cluster model if practical. The Dell NUC-era private cloud
should implement the three-cluster model for durable use.

## What a cluster means

A Kubernetes cluster is not “all machines connected to the same network.”

A cluster is the set of machines joined to the same Kubernetes control plane:

```text
API server
etcd
scheduler
controller manager
CNI state
worker nodes
```

Eighteen NUC-class machines on one network can be one cluster, three clusters, or
more. Cluster membership is an intentional lifecycle choice.

## Target clusters

### `nqlabs-management`

Purpose: run the control-plane and shared management services.

Likely services:

- ArgoCD
- Grafana / central dashboards
- Prometheus / Alertmanager or central observability aggregation
- Uptime Kuma / external probes
- Harbor
- OpenBao
- Authentik or Keycloak
- cluster lifecycle tooling
- backup orchestration

DNS for management/platform tools remains:

```text
*.platform.nqlabs.network
```

The cluster name is operator-facing; the DNS tier is user-facing. It is fine for a
cluster named `nqlabs-management` to host `argocd.platform.nqlabs.network`.

### `nqlabs-staging`

Purpose: run staging application workloads.

Example:

```text
cluster: nqlabs-staging
namespace: payment
host: payment.staging.nqlabs.network
```

### `nqlabs-production`

Purpose: run production application workloads.

Example:

```text
cluster: nqlabs-production
namespace: payment
host: payment.production.nqlabs.network
```

## Namespace model by phase

### Mac laptop lab

The Mac lab is a single cluster, so it approximates environment separation with
service-environment namespaces:

```text
namespace/<service>-staging
namespace/<service>-production
```

Example:

```text
namespace/demo-staging
namespace/demo-production
```

This prevents staging and production service instances from sharing namespace-scoped
secrets, quotas, limits, RBAC, and policies in the single-cluster lab.

### Desktop fixed-IP lab

The desktop has enough capacity to rehearse multi-cluster operation. Target hardware:

```text
AMD Ryzen 9 7950X
128GB RAM
2TB SSD
fixed IP
```

If practical, run three Talos VM clusters:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```

If starting smaller, keep the same logical names and document any temporary shortcuts.

Recommended host model:

```text
desktop bare metal: Proxmox VE or another KVM-based hypervisor
guest VMs: Talos nodes
```

Do not install Talos directly as the main desktop OS if the goal is multi-cluster
rehearsal. Talos is the OS for Kubernetes nodes, not a general-purpose VM host. A
desktop running Talos directly would become one Kubernetes node; it would not provide
the flexible VM lifecycle needed to rehearse `nqlabs-management`, `nqlabs-staging`,
and `nqlabs-production` on one physical machine.

### NUC cloud

The NUC-era target is true environment separation:

```text
cluster/nqlabs-staging    namespace/<service>
cluster/nqlabs-production namespace/<service>
```

The same namespace name may exist in both clusters because the cluster boundary
separates environments.

Example:

```text
nqlabs-staging/payment
nqlabs-production/payment
```

NUC nodes should run Talos directly on bare metal. At that phase, each physical
machine is intended to be a Kubernetes node, not a hypervisor for lab clusters.

## Why not one large cluster?

One 18-node cluster would share:

- API server
- etcd
- CNI state
- controllers
- admission policies
- cluster-scoped credentials
- failure domain

That is useful for capacity, but weaker for environment isolation. Staging and
production should not share this control-plane blast radius for serious workloads.

## Hardware allocation starting point

If the NUC pool has 18 machines, a starting allocation is:

```text
nqlabs-management: 3 nodes
nqlabs-staging:    6 nodes
nqlabs-production: 9 nodes
```

This can be changed later. The platform documentation should teach how to create new
clusters from new machines and how to drain/re-provision machines into a different
cluster when capacity needs change.

## Policy model

Cilium is the NQLabs CNI. Service isolation should prefer CiliumNetworkPolicy because
it supports richer controls than standard Kubernetes NetworkPolicy, including Cilium
identity/entity concepts, DNS/FQDN egress controls, and L7-aware policy options.

Standard NetworkPolicy can remain useful as a portable baseline, but production-like
service isolation should be expressed with CiliumNetworkPolicy.
