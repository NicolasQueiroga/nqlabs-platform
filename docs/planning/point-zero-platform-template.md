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

## Hardware inventory (collected)

- CPU: AMD Ryzen 9 7950X (16 cores / 32 threads)
- RAM: 124 GB
- Storage: 223 GB local-lvm SSD (only usable storage; 1.9 TB NVMe unmounted/reserved)
- NIC: single 1 GbE (vmbr0, flat LAN 192.168.15.0/24)
- No UPS
- Proxmox host IP: 192.168.15.20 (LAN) / 100.105.35.84 (Tailscale)
- Gateway: 192.168.15.1

## First attempt lessons (2026-06-25)

A first bootstrap attempt was made and cleaned up. Lessons learned:

1. **Talos v1.13 HostnameConfig**: The base `talosctl gen config` output includes a
   separate `HostnameConfig` document with `auto: stable`. Patching
   `machine.network.hostname` causes "static hostname is already set" error. Must
   patch the HostnameConfig document with `auto: off` + `hostname: <name>`.

2. **Proxmox boot order**: VMs created with ISO on `ide2` must have boot order set
   to `ide2` for initial boot, then changed to `scsi0` after Talos installs to disk.
   If left as `ide2`, nodes boot from ISO forever and never use the installed disk.
   Best approach: apply config with `--mode reboot`, let Talos install to disk via
   `talosctl upgrade`, then change boot order to `scsi0`.

3. **Talos install to disk**: `apply-config` in maintenance mode applies the config
   but does NOT install Talos to disk. The node runs from ISO with the config
   applied. Must run `talosctl upgrade --image ghcr.io/siderolabs/installer:v1.13.3`
   to install to disk. The upgrade uses kexec to reboot from disk.

4. **Stale iptables on Proxmox**: The old management cluster left iptables DROP
   rules on the Proxmox host blocking ports 8006 (web UI) and 22 (SSH) from LAN.
   Must clean these before starting: `iptables -D INPUT -p tcp --dport 8006 -j DROP`
   and `iptables -D INPUT -p tcp --dport 22 -j DROP`.

5. **Cilium ServiceMonitor**: Cilium values have `hubble.metrics.serviceMonitor.enabled: true`
   which requires Prometheus CRDs (ServiceMonitor). Must disable with
   `--set hubble.metrics.serviceMonitor.enabled=false` for bootstrap install.

6. **ArgoCD ExternalSecret dependency**: ArgoCD values include `extraObjects` that
   create an ExternalSecret (requires ESO CRDs). Must use a bootstrap values file
   without `extraObjects` for initial install. After ESO is installed via GitOps,
   ArgoCD can manage itself with the full values.

7. **Proxmox resource pressure**: 3 VMs with 4 vCPU / 24 GB RAM each on a 16-core
   host was fine after settling, but during simultaneous boot the Proxmox host was
   unresponsive (SSH and web UI down). Consider 2 vCPU per VM, or stagger VM starts.

8. **talosconfig endpoints**: Generated talosconfig has `endpoints: []`. Must be
   populated with node IPs before using `talosctl` commands that require auth.

## Correct bootstrap sequence (validated)

```txt
1. Clean Proxmox: remove stale iptables, verify free storage
2. Create VMs with correct settings:
   - 2 vCPU, 24 GB RAM (reduced from 4 vCPU to avoid host starvation)
   - 32 GB system disk (scsi0) + 10 GB Ceph OSD disk (scsi1)
   - Boot order: ide2 (ISO) for initial boot
   - Talos ISO v1.13.3 on ide2
   - onboot: 1 (auto-start with Proxmox)
3. Wait for VMs to boot from ISO (DHCP IPs, Talos API on port 50000)
4. Generate Talos configs:
   - talosctl gen config nqlabs-management https://192.168.15.9:6443
   - Patch with HostnameConfig (auto: off, hostname: mgmt-XX)
   - Patch with static IPs, VIP, Cilium CNI (none), kube-proxy disabled
5. Apply configs: talosctl apply-config --insecure --nodes <dhcp-ip> --file <config> --mode reboot
6. Wait for nodes to come up on static IPs
7. Bootstrap etcd: talosctl bootstrap --nodes <first-node>
8. Wait for cluster health
9. Install Talos to disk: talosctl upgrade --image ghcr.io/siderolabs/installer:v1.13.3
10. Change Proxmox boot order to scsi0 for all VMs
11. Get kubeconfig
12. Install Gateway API CRDs
13. Install Cilium (with --set hubble.metrics.serviceMonitor.enabled=false)
14. Apply LB IPAM pool
15. Install ArgoCD with bootstrap values (no ExternalSecret, admin enabled)
16. Get ArgoCD admin password
17. Apply root Application for GitOps
```

## VM topology (decided)

```yaml
mgmt-01:
  vmid: 101
  cpu: 2 vCPU
  memory: 24 GB
  disks:
    - scsi0: 32 GB (system, local-lvm)
    - scsi1: 10 GB (Ceph OSD, local-lvm)
  network:
    mac: BC:24:11:15:00:10
    ip: 192.168.15.10/24
    gateway: 192.168.15.1
    vip: 192.168.15.9
  hostname: mgmt-01

mgmt-02:
  vmid: 102
  cpu: 2 vCPU
  memory: 24 GB
  disks:
    - scsi0: 32 GB (system, local-lvm)
    - scsi1: 10 GB (Ceph OSD, local-lvm)
  network:
    mac: BC:24:11:15:00:11
    ip: 192.168.15.11/24
    gateway: 192.168.15.1
    vip: 192.168.15.9
  hostname: mgmt-02

mgmt-03:
  vmid: 103
  cpu: 2 vCPU
  memory: 24 GB
  disks:
    - scsi0: 32 GB (system, local-lvm)
    - scsi1: 10 GB (Ceph OSD, local-lvm)
  network:
    mac: BC:24:11:15:00:12
    ip: 192.168.15.12/24
    gateway: 192.168.15.1
    vip: 192.168.15.9
  hostname: mgmt-03
```

## Network plan

```txt
LAN: 192.168.15.0/24 (flat, vmbr0)
Gateway: 192.168.15.1
Proxmox: 192.168.15.20
VIP: 192.168.15.9 (Kubernetes API, shared across control-plane)
mgmt-01: 192.168.15.10
mgmt-02: 192.168.15.11
mgmt-03: 192.168.15.12
LB pool: 192.168.15.194-195 (Cilium LB IPAM)
Pod CIDR: 10.244.0.0/16
Service CIDR: 10.96.0.0/12
```

## Immediate next tasks

1. ~~Collect Proxmox desktop hardware inventory~~ (done)
2. ~~Decide management VM topology from actual resources~~ (done: 3 VMs, 2 vCPU, 24 GB each)
3. Add `clusters/nqlabs-management/machines.yaml` for Proxmox VMs
4. Build Proxmox VM creation automation (script)
5. Build Talos config render + apply automation (script)
6. Design Rook/Ceph disk layout for management VMs
7. Add OpenBao architecture decision and bootstrap procedure
8. Add supply-chain admission design
9. Add Cilium policy validation to CI

## Open questions

- ~~Exact desktop Proxmox hardware specs?~~ (answered)
- Use Terraform provider for Proxmox, OpenTofu, or shell/API first?
- How many dedicated virtual disks can each Talos VM receive for Ceph OSDs? (current: 1 x 10 GB)
- ~~Will the Proxmox desktop have multiple NICs/VLANs or one flat LAN initially?~~ (flat LAN)
- Should management run all workloads on control-plane nodes, or split worker/storage VMs if resources allow?
- What is the external object storage target for disaster backups before Rook/Ceph exists?

