# Runbook: Cluster Lifecycle

This runbook defines how NQLabs creates clusters, adds machines, and moves machines
between clusters. It applies first to desktop Proxmox VMs and later to NUC bare
metal nodes.

The desktop is not a toy prerequisite phase. It is powerful enough to build the full
`nqlabs-management` / `nqlabs-staging` / `nqlabs-production` architecture as Talos
VM clusters. NUCs later add bare-metal nodes/capacity to that same architecture or
replace VM nodes after validation; they do not unlock separate platform capabilities.

## Operating rules

- Git is the source of truth for intended topology, patches, runbooks, and inventory.
- Generated Talos secrets, machine configs, `talosconfig`, and kubeconfigs are never
  committed. They live under `clusters/<cluster>/generated/` and in 1Password.
- A machine belongs to exactly one Kubernetes cluster at a time.
- Moving a machine between clusters means drain/reset/re-provision. Do not casually
  point an existing node at another control plane.
- Multi-cluster and Phase 2 security/operations work starts on desktop Proxmox VMs.
  NUCs are node/capacity expansion, not a reason to defer architecture.

## Per-cluster repository shape

Every cluster should have a folder:

```text
clusters/<cluster-name>/
├── README.md              # cluster purpose, inventory, bootstrap notes
├── patches/               # safe Talos config patches/templates
└── generated/             # gitignored: secrets, machine configs, kubeconfig
```

Current and target folders:

```text
clusters/desktop-lab/       # active one-cluster desktop substrate validation
clusters/nqlabs-management/ # target management/platform cluster
clusters/nqlabs-staging/    # target staging workload cluster
clusters/nqlabs-production/ # target production workload cluster
```

## Cluster identity checklist

Before creating a cluster, fill these values in the cluster README and IP plan:

| Field | Example |
|-------|---------|
| Cluster name | `nqlabs-management` |
| Purpose | platform/control services |
| Environment tier | `platform` / `staging` / `production` |
| Proxmox VMIDs | `131` |
| Node names | `talos-management-cp-01` |
| Node IPs | `192.168.15.31` |
| Talos control-plane endpoint | node IP for single-node, VIP/LB later |
| Cilium LB pool or reserved LB IPs | unique per cluster |
| Gateway IP | unique per cluster if it exposes HTTP(S) |
| DNS role | authoritative DNS, workload ingress, none |
| ArgoCD relationship | local root or registered to management ArgoCD |
| 1Password item | Talos secrets item name |

## Create a new cluster from zero

Use this for each desktop VM cluster and later for NUC bare metal.

### 1. Allocate identity and capacity

1. Choose cluster name and purpose.
2. Allocate node names, VMIDs/hardware IDs, MACs, IPs, CPU/RAM/disk.
3. Allocate unique LoadBalancer/Gateway addresses if the cluster will expose services.
4. Update:
   - `docs/decisions/ip-address-plan.md`
   - `docs/decisions/cluster-topology.md` if the topology changes
   - `clusters/<cluster>/README.md`

### 2. Create machines

For desktop Proxmox VMs:

1. Create VM(s) with UEFI, q35, virtio disk, virtio NIC, bridge `vmbr0`.
2. Attach Talos amd64 ISO.
3. Use thin disks on `local-lvm` unless a later storage decision changes this.
4. Enable autostart only after Talos is installed and stable.

For NUC bare metal later:

1. Use the same cluster inventory model.
2. Replace VMIDs with physical asset IDs / serials.
3. Use the target cluster's existing Talos secrets/config generation model.
4. Boot/install Talos directly on the machine.
5. Join the NUC to `nqlabs-management`, `nqlabs-staging`, or `nqlabs-production`.

### 3. Generate Talos secrets and configs

From the Mac/control workstation:

```bash
cluster=nqlabs-management
mkdir -p clusters/$cluster/{patches,generated}

talosctl gen secrets -o clusters/$cluster/generated/secrets.yaml
```

Immediately store `clusters/$cluster/generated/secrets.yaml` in 1Password.
Recommended item naming:

```text
NQLabs / talos-<cluster>-secrets
```

Generate configs:

```bash
export TALOS_ENDPOINT=<first-control-plane-ip>

talosctl gen config \
  --with-secrets clusters/$cluster/generated/secrets.yaml \
  --config-patch-control-plane @clusters/$cluster/patches/controlplane.yaml \
  $cluster \
  https://$TALOS_ENDPOINT:6443 \
  --output-dir clusters/$cluster/generated
```

For worker nodes, add `--config-patch-worker @clusters/$cluster/patches/worker.yaml`
when a worker patch exists.

### 4. Apply Talos config and bootstrap

For the first control-plane node:

```bash
talosctl apply-config \
  --insecure \
  --nodes <control-plane-ip> \
  --file clusters/$cluster/generated/controlplane.yaml

# wait until Talos API is available, then:
talosctl --talosconfig clusters/$cluster/generated/talosconfig \
  --nodes <control-plane-ip> \
  bootstrap

talosctl --talosconfig clusters/$cluster/generated/talosconfig \
  --nodes <control-plane-ip> \
  kubeconfig clusters/$cluster/generated/kubeconfig
```

Validation:

```bash
export KUBECONFIG=$PWD/clusters/$cluster/generated/kubeconfig
kubectl get nodes -o wide
```

### 5. Install baseline networking before GitOps

A new Talos cluster has no CNI until Cilium is installed.

Required order:

1. Install Gateway API CRDs.
2. Install Cilium with cluster-specific `k8sServiceHost` and Cilium values.
3. Validate node Ready and pod networking.
4. Apply Cilium LB IPAM/L2 config for that cluster's unique LB range.

Only after Cilium is healthy should ArgoCD/root GitOps be bootstrapped.

### 6. Bootstrap GitOps or register with management

For the temporary single desktop-lab cluster, bootstrap root ArgoCD locally.

For the final three-cluster topology:

- `nqlabs-management` runs ArgoCD and shared platform tools.
- `nqlabs-staging` and `nqlabs-production` are registered as external clusters in
  management ArgoCD.
- Service Applications target the staging/production cluster destinations rather
  than fake separation inside one cluster.

Exact ArgoCD multi-cluster registration commands should be added when
`nqlabs-management` is live.

## Add a node to an existing cluster

Use this when adding a worker/control-plane VM or later adding a NUC as a node to an existing cluster.

1. Confirm cluster has capacity and a reason for the new node.
2. Allocate node identity in the IP plan and cluster README.
3. Create the VM/physical machine.
4. Generate or select the correct machine config using the existing cluster secrets.
5. Apply config to the new machine.
6. Validate:

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
cilium status
```

7. If storage is present, validate storage rebalance/health before scheduling critical
   workloads onto the new node.



## Add NUCs to the existing architecture

NUCs are not a separate platform phase that unlocks new services. Use them as
bare-metal nodes/capacity for the clusters already built on the desktop.

For each NUC:

1. Choose target cluster: `nqlabs-management`, `nqlabs-staging`, or
   `nqlabs-production`.
2. Add the NUC to that cluster's inventory with hostname, MAC, IP, role, and storage
   disks.
3. Generate the machine config using the target cluster's existing Talos secrets.
4. Install/apply Talos to the NUC.
5. Validate the mixed VM + bare-metal cluster.
6. Only after validation, optionally drain and remove the Proxmox VM node it replaces.

This preserves cluster identity and GitOps registration. The goal is capacity and
hardware durability, not a new architecture.

## Move a machine from one cluster to another

Use this when reallocating capacity, for example moving a node from staging to
production.

1. Confirm the old cluster can lose the node.
2. Cordon and drain:

```bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

3. Remove or reset the node from the old cluster.
4. Wipe Talos state before reusing the machine.
5. Update both source and target cluster inventory docs.
6. Apply the target cluster Talos machine config.
7. Validate node health, Cilium health, storage health, and workload scheduling.

## Desktop multi-cluster ingress model

On the desktop, clients should continue to use Tailscale-only DNS and the Proxmox
HAProxy edge:

```text
client on tailnet
  -> *.nqlabs.network resolves to 100.105.35.84
  -> HAProxy on Proxmox tailscale0
  -> SNI routes to the correct cluster Gateway
```

Initial fanout target:

| Hostname pattern | Cluster | Backend Gateway |
|------------------|---------|-----------------|
| `*.platform.nqlabs.network` | `nqlabs-management` | management Gateway IP |
| `*.staging.nqlabs.network` | `nqlabs-staging` | staging Gateway IP |
| `*.production.nqlabs.network` | `nqlabs-production` | production Gateway IP |

Until the three-cluster topology exists, the current desktop-lab HAProxy forwards all
HTTP(S) traffic to the single desktop-lab Gateway.
