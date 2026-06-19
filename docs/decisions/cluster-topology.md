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
is where the full architecture is built first: it should first prove one desktop
Talos cluster, then run the three-cluster model as VMs. NUCs later add bare-metal
nodes/capacity to that same model or replace VM nodes after validation; they do not
unlock a separate architecture.

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

The desktop is the next infrastructure host and the virtualized NUC rehearsal. The
Mac remains the development/control workstation for editing code, running CLI tools,
and pushing GitOps changes. The desktop runs Proxmox/KVM and Talos VMs. See
`docs/runbooks/desktop-lab-bootstrap.md` for the bootstrap procedure.

The desktop has enough capacity to rehearse multi-cluster operation. Target hardware:

```text
AMD Ryzen 9 7950X
124GB RAM usable by Proxmox
223.6GB active Proxmox system SSD with 130.3GB local-lvm thin VM storage
1.9TB secondary SSD present as NTFS, not assigned to Proxmox yet
fixed IP
```

Storage policy for the desktop rehearsal: be CPU/RAM-rich but disk-conscious. Run
thin VM disks, short observability retention, and no real data-platform workloads on
the active 130GB VM pool. The full topology can still be rehearsed by keeping each
cluster lean. Repurpose the 1.9TB disk only after an explicit wipe/format decision.

After one `nqlabs-desktop-lab` bootstrap cluster proves the substrate, run three
Talos VM clusters:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```

The one-cluster bootstrap is a temporary substrate validation step. The architecture
rehearsal target is the three-cluster topology above.

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

### NUC node expansion / hardware migration

The NUC phase should not invent a new topology or defer platform capabilities. The
management/staging/production model should already exist on the desktop. NUCs are
then added as bare-metal nodes to the existing clusters, or used to replace Proxmox
VM nodes after the bare-metal nodes are healthy.

The target remains true environment separation:

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

NUC nodes should run Talos directly on bare metal. Each physical machine is intended
to be a Kubernetes node added to `nqlabs-management`, `nqlabs-staging`, or
`nqlabs-production`, not a hypervisor for separate lab clusters.

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

## Hardware/node allocation starting point

If the NUC pool has 18 machines, a starting node allocation into the existing clusters is:

```text
nqlabs-management: 3 nodes
nqlabs-staging:    6 nodes
nqlabs-production: 9 nodes
```

This can be changed later. The platform documentation should teach how to add new
nodes to existing clusters, how to create an additional cluster only when deliberately
needed, and how to drain/re-provision machines when capacity needs change.

Node expansion path:

1. Add NUC nodes to the target cluster using that cluster's Talos secrets/configs.
2. Validate Kubernetes, Cilium, storage, and workload scheduling on the mixed VM +
   bare-metal cluster.
3. Drain/remove Proxmox VM nodes only after bare-metal capacity is healthy.
4. Keep the cluster identity (`nqlabs-management`, `nqlabs-staging`,
   `nqlabs-production`) stable throughout the transition.


## Policy model

Cilium is the NQLabs CNI. Service isolation should prefer CiliumNetworkPolicy because
it supports richer controls than standard Kubernetes NetworkPolicy, including Cilium
identity/entity concepts, DNS/FQDN egress controls, and L7-aware policy options.

Standard NetworkPolicy can remain useful as a portable baseline, but production-like
service isolation should be expressed with CiliumNetworkPolicy.
