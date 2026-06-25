# Point-Zero Platform Template Progress

Status: planning started 2026-06-25  
Owner: NQLabs Platform  
Goal: rebuild the complete private-cloud platform from empty hardware using Git, a small bootstrap secret bundle, and repeatable automation.

## Mission

The point-zero template is the baseline platform shape. It is not a minimal demo and it is not a temporary homelab shortcut. If the environment must be rebuilt from zero, this template should create a management cluster first, then use that management plane to provision staging and production clusters, ending with a platform ready to run real applications.

Success condition:

```txt
fresh hardware + repo + bootstrap bundle
→ management cluster online
→ PXE/provisioning online
→ staging and production clusters provisioned
→ GitOps reconciles all foundation apps
→ service factory can deploy signed/scanned apps
→ ArgoCD/Gatus/observability show green
```

## Locked decisions

### Management cluster uses the whole current Proxmox desktop

The current desktop running Proxmox is dedicated entirely to the NQLabs management cluster. Its hardware resources should be consumed by management-cluster VMs, not split between ad-hoc workloads.

The desktop Proxmox host should create the best number of Talos VM nodes possible from available CPU, RAM, SSD/NVMe, and networking capacity.

Baseline target:

```txt
minimum: 3 Talos VMs for management control-plane quorum
preferred: odd number of control-plane nodes where resources allow, plus worker/storage separation only if hardware can sustain it
```

Sizing must be finalized after hardware inventory, but the management cluster must be large enough to run:

- ArgoCD
- Authentik
- OpenBao
- Rook/Ceph
- observability control plane
- PXE/provisioning service
- DNS and platform gateway
- policy/security stack

### Point-zero includes real baseline components

Point-zero includes everything the platform already has and will maintain, plus the missing baseline components. These are not optional later add-ons.

Included from day zero:

- Talos Linux
- Kubernetes
- Cilium CNI
- Cilium Gateway API
- Cilium LB IPAM
- CiliumNetworkPolicy guardrails
- CoreDNS split-horizon DNS
- ArgoCD GitOps
- ApplicationSets
- cert-manager
- External Secrets Operator
- Authentik
- CloudNativePG
- Velero
- Prometheus / Thanos / Grafana
- Loki / Promtail
- Tempo
- Pyroscope
- OpenTelemetry Collector
- Gatus
- Falco
- Kyverno
- Argo Rollouts
- service-factory chart and delivery conventions
- Rook/Ceph
- OpenBao
- Cosign image signing
- Trivy CI scanning
- admission enforcement for signed/scanned images

## Desired topology

### Phase 0 physical/VM topology

```txt
Proxmox desktop
└── nqlabs-management
    ├── mgmt-01 Talos VM
    ├── mgmt-02 Talos VM
    └── mgmt-03 Talos VM
```

The exact VM count can increase if resources allow. The first hard requirement is etcd quorum and enough capacity for the full management control plane.

### Future bare-metal topology

Minimum production-shaped target:

```txt
management: 3+ machines or VMs
staging:    3+ machines
production: 3+ machines

minimum total for real HA shape: 9 nodes
```

When more physical machines are available, management provisions the remaining `n >= 6` machines into staging and production:

```txt
management cluster
├── PXE/provisioning service
├── staging cluster factory
└── production cluster factory
```

## Bootstrap model

Management cannot depend on management-hosted PXE before management exists. Therefore the rebuild process has two layers:

```txt
Layer 0: seed bootstrap
  laptop/manual/USB/minimal PXE creates the management Talos cluster

Layer 1: self-hosted metal factory
  management cluster provisions every other cluster/node
```

The seed layer should be tiny and boring. Everything after ArgoCD is up must come from GitOps.

## Bootstrap order

Target order:

```txt
0. Seed bootstrap secrets
1. Talos management cluster
2. Cilium
3. ArgoCD
4. Rook/Ceph
5. OpenBao
6. ESO wired to OpenBao
7. cert-manager + internal/public PKI flows
8. Authentik
9. observability/security stack
10. PXE/provisioning service
11. staging/prod cluster factory
12. service factory
```

Reasoning:

- Storage and secrets are platform primitives, not application add-ons.
- Rook/Ceph should replace local-path as default durable storage.
- OpenBao should replace 1Password as the operational secret backend.
- Cosign/Trivy/admission must exist before production application delivery is trusted.

## Required workstreams

### 1. Hardware and VM inventory

Create declarative inventory for the Proxmox desktop and future physical machines.

Required fields:

```yaml
machines:
  - name: mgmt-01
    type: proxmox-vm
    cluster: nqlabs-management
    role: control-plane
    cpu: TBD
    memory: TBD
    disks:
      - name: system
        size: TBD
      - name: ceph
        size: TBD
    network:
      mac: TBD
      ip: TBD
```

Inventory should drive:

- Proxmox VM creation
- DHCP reservations
- PXE matching
- Talos machine configs
- DNS records
- cluster labels
- ArgoCD cluster registration
- Cilium LB pools

### 2. Deterministic network plan

Define subnets/VLANs even if the first implementation uses a flat LAN.

Needed categories:

- management/API network
- PXE/provisioning network
- Kubernetes pod/service CIDRs
- Cilium LB IP pools
- storage network, if hardware/network allows
- public edge network
- Tailscale/split-DNS reachability

### 3. Management bootstrap kit

Create a seed workflow:

```txt
bootstrap/management/
  inventory.yaml
  talos-patches/
  render.sh
  bootstrap.sh
  README.md
```

Expected commands:

```bash
make render-management
make create-management-vms
make install-management
make bootstrap-management
make kubeconfig-management
make install-argocd
```

### 4. Rook/Ceph baseline

Management cluster must include Rook/Ceph from point zero.

Required decisions:

- VM disk layout for Ceph OSDs
- failure-domain model for Proxmox-hosted VMs
- default StorageClasses
- retain/delete policies
- CNPG storage class
- object storage strategy for backups/artifacts

Initial target StorageClasses:

```txt
ceph-rbd-retain
ceph-rbd-delete
cephfs-retain
```

`local-path` may exist only as bootstrap scratch/emergency storage, not as default platform storage.

### 5. OpenBao baseline

OpenBao must be installed before normal platform secrets move beyond bootstrap.

Target model:

```txt
1Password → bootstrap/emergency only
OpenBao   → operational secrets backend
ESO       → syncs from OpenBao
```

Needed capabilities:

- initialization/unseal procedure
- storage backend decision
- recovery keys procedure
- ESO ClusterSecretStore backed by OpenBao
- dynamic credentials roadmap
- PKI/transit roadmap

### 6. Supply-chain baseline

Application delivery must require signed/scanned artifacts.

Required from point zero:

- Trivy in CI
- SBOM generation
- Cosign signing in CI
- Kyverno admission policy for image signature verification
- policy exceptions only through reviewed platform PRs

Future hardening:

- critical/high vulnerability admission gating where practical
- continuous in-cluster scanning
- provenance/SLSA attestations

### 7. PXE/provisioning service

Management cluster hosts provisioning for all non-management nodes.

Recommended progression:

```txt
Phase 1: simple Talos PXE using DHCP/iPXE/HTTP or matchbox-style flow
Phase 2: Cluster API Talos provider
Phase 3: Metal3/Ironic only when hardware has BMC/IPMI/Redfish
```

Do not overbuild Metal3 before hardware supports automated power control.

### 8. Workload cluster factory

Management GitOps should own staging/production cluster definitions.

Target structure:

```txt
clusters/
  nqlabs-management/
  nqlabs-staging/
    machines.yaml
    talos/
    cilium/
    gateway/
    apps/
  nqlabs-production/
    machines.yaml
    talos/
    cilium/
    gateway/
    apps/
```

Creating or rebuilding a cluster should be mostly inventory + GitOps:

```bash
git add clusters/nqlabs-staging/*
git push
```

Then management reconciles PXE config, Talos config, cluster registration, and foundation apps.

### 9. Validation pipeline

CI must catch platform-breaking YAML before ArgoCD does.

Required validators:

- kubeconform
- helm template/lint
- Talos config validation
- Kyverno policy tests
- Cilium policy validation/dry-run
- ArgoCD app diff where possible
- checks that gateway-backed services use CiliumNetworkPolicy `fromEntities: ingress`
- checks that CNP/CCNP do not use invalid `ingress: []`
- checks that default-deny guardrails do not use `ingressDeny` unless explicitly approved

## Current known decisions and lessons to preserve

- Cilium Gateway traffic must be allowed with CiliumNetworkPolicy `fromEntities: ingress`, not Kubernetes NetworkPolicy namespace selectors.
- Gateway allow policy target port is the pod port, not the service port.
- Cilium default-deny-only CNP/CCNP must use a valid no-op rule such as `fromEndpoints: []`, not `ingress: []`.
- CNPG namespaces with default-deny need operator ingress to port 8000 and CNPG pod egress to the Kubernetes API server.
- Talos PSA baseline means privileged namespaces such as monitoring must be labeled before privileged DaemonSets schedule.
- `refreshPolicy: CreatedOnce` ESOs can freeze `Ready=False`; recovery is delete-target-Secret after confirming provider access.

## Progress checklist

Legend:

```txt
[x] done
[~] partially exists / needs hardening
[ ] not started
```

### Existing platform foundation

- [x] Talos Kubernetes baseline
- [x] Cilium Gateway API baseline
- [x] ArgoCD GitOps baseline
- [x] cert-manager baseline
- [x] External Secrets Operator baseline
- [x] Authentik baseline
- [x] observability baseline
- [x] Kyverno/Falco baseline
- [x] Velero baseline
- [x] Argo Rollouts baseline
- [x] service-factory foundations
- [~] Cilium policy guardrails, recently fixed; needs CI validation

### Point-zero additions

- [ ] Proxmox desktop management-cluster VM inventory
- [ ] 3+ VM management topology finalized
- [ ] Proxmox VM creation automation
- [ ] Rook/Ceph deployed and defaulted
- [ ] OpenBao deployed and backed up
- [ ] ESO moved from 1Password operational source to OpenBao
- [ ] Cosign signing in CI
- [ ] Trivy CI gate
- [ ] admission verification for signed/scanned images
- [ ] PXE/provisioning service
- [ ] staging/prod automated cluster lifecycle
- [ ] automatic ArgoCD cluster registration
- [ ] full rebuild drill

## Immediate next tasks

1. Collect Proxmox desktop hardware inventory:
   - CPU model / core count
   - RAM
   - disk layout and free capacity
   - NIC count/speed
   - UPS status
2. Decide management VM topology from actual resources.
3. Add `clusters/nqlabs-management/machines.yaml` for Proxmox VMs.
4. Build Proxmox VM creation automation.
5. Design Rook/Ceph disk layout for management VMs.
6. Add OpenBao architecture decision and bootstrap procedure.
7. Add supply-chain admission design.
8. Add Cilium policy validation to CI.

## Open questions

- Exact desktop Proxmox hardware specs?
- Use Terraform provider for Proxmox, OpenTofu, or shell/API first?
- How many dedicated virtual disks can each Talos VM receive for Ceph OSDs?
- Will the Proxmox desktop have multiple NICs/VLANs or one flat LAN initially?
- Should management run all workloads on control-plane nodes, or split worker/storage VMs if resources allow?
- What is the external object storage target for disaster backups before Rook/Ceph exists?

