# NQLabs Platform — Build Plan

This document breaks down every problem that needs to be solved to build the NQLabs Platform,
organized by phase and layer. It evolves as work progresses.

---

## Phases

| Phase | Target Environment | Lifecycle Level | Goal |
|-------|--------------------|-----------------|------|
| **0 — Foundation** | Mac laptop / UTM | L1 → L2 | Prove the stack works end-to-end on a single node |
| **0.7 — Fixed-IP Desktop Full Architecture** | Ryzen 9 7950X / 124GB RAM desktop; 130GB active Proxmox thin storage | L2 → L5 | Build the full management/staging/production platform as Talos VM clusters |
| **1 — Hardware Node Expansion** | Dell NUC-class node pool | L5 → L5/L6 | Add bare-metal capacity/nodes to the already-built architecture; do not gate capabilities here |
| **2 — Operations/Security Hardening** | Same architecture, beginning on desktop | L5 → L6 | Full automation, DR, security, registry, policy, tracing, and lifecycle maturity |

Progress language matters: “operationally live” is not the same as “complete.” A
capability is complete only when it is implemented, validated, documented, and its
known production-readiness gaps are explicitly tracked. Nothing is discarded because
there are not enough real services yet; the platform should be ready before demand
arrives.

Repository boundary matters too: the final platform repo should contain architecture,
SRE/infrastructure, cluster lifecycle, reusable platform tooling, policies, runbooks,
and guides — not product application code. Current `apps/` and `services/` demo
content is allowed only as bootstrap/proof material. When the multi-repo service
delivery model is proven, clean the repo so it contains exactly what the platform
needs and move real applications to their own repositories.

---

## Phase 0 — Foundation (Laptop / VM Testing)

The goal is a single-node Talos Kubernetes cluster running locally in VMs,
with the full platform stack deployed via GitOps, accessible over Tailscale.

### Problem: Repository Structure

Everything starts here. Git is the source of truth.

**Tasks:**
- [x] Initialize git repository in `/home-lab`
- [x] Define top-level directory structure (see below)
- [x] Set up `.gitignore` for secrets, temp files
- [x] Choose a secrets strategy before committing anything (see Identity layer)
- [x] Document directory layout in `docs/repo-structure.md`

**Proposed repo structure:**
```
home-lab/
├── .github/workflows/     # CI/release automation
├── clusters/              # Per-cluster Talos + ArgoCD bootstrap
│   └── lab/               # Laptop/VM test cluster
├── infrastructure/        # Platform services (ArgoCD apps)
│   ├── networking/        # Cilium, ingress, DNS
│   ├── storage/           # Storage provisioner
│   ├── monitoring/        # Prometheus, Grafana, Alertmanager, Loki/Promtail
│   ├── security/          # cert-manager, external-secrets
│   └── identity/          # Future: SSO, workload identity
├── platform/              # Higher-order platform services
│   └── argocd/            # ArgoCD itself (app-of-apps)
├── apps/                  # Service environment contracts consumed by ApplicationSet
├── services/              # Build contexts for first-party service images
├── terraform/             # Service/product onboarding definitions and modules
├── charts/                # Platform-owned reusable Helm charts
├── docs/                  # Architecture decisions, runbooks
│   └── decisions/         # ADRs — Architecture Decision Records
├── guides/                # Educational curriculum
└── scripts/               # Bootstrap and utility scripts
```

**Decision to make:**
- Helm-only, Kustomize-only, or both? → Recommendation: Kustomize for platform layer,
  Helm charts wrapped in ArgoCD Applications for third-party services.

---

### Problem: Talos Linux — Single Node (Laptop)

Talos runs in VMs on the laptop for local testing using **UTM** (M1 Pro MacBook).

**Architecture note:** The laptop is ARM64 (Apple M1 Pro). The NUCs are x86_64.
UTM on Apple Silicon runs ARM64 VMs natively (full speed). We use ARM64 Talos images
for local testing. Production NUC images will be amd64 — configs are identical,
only the image architecture differs. Most container images support both architectures.

**Laptop specs:** M1 Pro, 10 cores (8P+2E), 16GB RAM, ~800GB free disk.
VM budget: 2–3 VMs comfortably (e.g. 1 control-plane + 1 worker, or 1 combined).

**Tasks:**
- [x] Install `talosctl` CLI (`brew install siderolabs/tap/talosctl`)
- [x] Install `kubectl` (`brew install kubectl`)
- [x] Install UTM (`brew install --cask utm`)
- [x] Download Talos ISO for ARM64 (`metal-arm64.iso`) from GitHub releases
- [x] Create UTM VM: 4 vCPU, 6GB RAM, 50GB disk, virtio networking
- [x] Configure VM networking: **UTM Shared Network (NAT)** on `192.168.64.0/24`
- [x] Define Talos machine config for single control-plane node (with worker role too)
- [x] Generate Talos secrets (`talosctl gen secrets`) — store in 1Password, NOT in git
- [x] Apply config and bootstrap the cluster
- [x] Document bootstrap procedure in `docs/runbooks/talos-bootstrap-laptop.md`
- [x] Validate: `kubectl get nodes` returns Ready

**VM networking:** UTM Shared Network gives the VM an IP on `192.168.64.0/24`, which
keeps the laptop lab self-contained. Cilium L2 announcements and Tailscale subnet
routing make service IPs reachable from the host/tailnet.

---

### Problem: GitOps Delivery — ArgoCD Bootstrap

ArgoCD is the delivery layer. It must be bootstrapped before it can manage itself.

**Tasks:**
- [x] Define ArgoCD installation manifests in `platform/argocd/`
- [x] Bootstrap ArgoCD into the cluster (initial `kubectl apply`)
- [x] Define App-of-Apps pattern: one root Application that manages all others
- [x] Configure ArgoCD to sync from this git repository
- [x] Secure ArgoCD admin credentials (rotate default password)
- [x] Expose ArgoCD UI (internally, via Gateway API) — https://argocd.platform.nqlabs.network
- [x] Add ArgoCD self-management Application — ArgoCD now manages its own Helm release from git
- [x] Configure global ArgoCD diff customizations for controller-defaulted fields (Gateway API + ExternalSecret)
- [x] Validate: ArgoCD syncs and reconciles platform apps

**Key decisions:**
- ArgoCD install method: plain manifests vs Helm chart
- Repository: public (simpler) or private (requires deploy key/token in ArgoCD)
- Sync policy: manual vs automated with self-heal

---

### Problem: Networking — CNI and Load Balancer

Cilium is the CNI of choice. It replaces kube-proxy, provides eBPF networking,
built-in load balancer, and Hubble for network observability.

**Tasks:**
- [x] Install Cilium as CNI (configured before/during Talos cluster init)
- [x] Replace kube-proxy with Cilium (kube-proxy-free mode)
- [x] Enable Cilium LB IPAM (replaces MetalLB) — pool 192.168.64.192/28, L2 on enp0s1
- [x] Enable Hubble (Cilium's network observability layer)
- [x] Validate: pods can communicate, services get external IPs
- [x] Document IP address plan (which IP ranges are used for what) — `docs/decisions/ip-address-plan.md`

**Key decisions:**
- IP pool for LoadBalancer services (e.g. `192.168.x.x/24` subnet)
- BGP mode vs L2 announcements for LB IPs (L2 is simpler for home lab)

---

### Problem: Networking — Ingress

HTTP/HTTPS traffic routing into the cluster via **Cilium Gateway API**.

Cilium's built-in Gateway API implementation uses the Envoy proxy already running
in the cluster. No separate ingress controller is deployed.

Gateway API replaces the legacy `Ingress` resource with structured, role-aware CRDs:
`GatewayClass` → `Gateway` → `HTTPRoute` / `TLSRoute` / `GRPCRoute`

**Tasks:**
- [x] Enable `gatewayAPI.enabled: true` in Cilium values
- [x] Install upstream Gateway API CRDs (standard + experimental bundles)
- [x] Upgrade Cilium to activate Gateway API mode
- [x] Verify `GatewayClass` named `cilium` is created automatically
- [x] Define a `Gateway` for internal `nqlabs.network` services — platform-gateway at 192.168.64.193
- [x] Test with an `HTTPRoute` pointing to a dummy service — ArgoCD HTTPRoute working

---

### Problem: Networking — DNS

**Architecture:** Tailscale is the access and DNS layer throughout all phases. No
AdGuard Home or Pi-hole needed.

How it works:
- **Tailscale Operator** (runs in the cluster) registers selected services directly on
  your tailnet. They get Tailscale IPs and are reachable from any tailnet device.
- **Tailscale split DNS** (configured in the admin console) routes all `nqlabs.network`
  queries to a dedicated in-cluster nameserver.
- **In-cluster CoreDNS** (a standalone deployment, separate from Kubernetes' own CoreDNS)
  serves as the authoritative nameserver for `nqlabs.network`. external-dns writes records
  to it automatically whenever an Ingress or Service is created/updated.
- Result: every tailnet device resolves `*.nqlabs.network` automatically, with zero
  per-device configuration.

**Phase 0 (laptop VM — everything local):**
Tailscale is not strictly needed to access the cluster since you and the VM share the
same machine. Use `/etc/hosts` during initial bring-up, then add the Tailscale Operator
once the cluster is healthy to begin testing the full DNS flow.

**Distributed/multi-node target:**
Full flow active: Tailscale Operator → split DNS → in-cluster CoreDNS ← external-dns.

**Tasks:**
- [x] Understand Kubernetes CoreDNS role: cluster-internal DNS only (pod/service discovery)
- [x] Deploy **standalone CoreDNS** as authoritative nameserver for `nqlabs.network`
  - etcd backend (gcr.io/etcd-development/etcd:v3.5.21), ClusterIP 10.103.246.202
  - LB IP: 192.168.64.192 (Cilium IPAM), Tailscale IP: 100.125.207.63
- [x] Install **external-dns** configured to write to the standalone CoreDNS/etcd backend
- [x] Install **Tailscale Operator** in the cluster
- [x] Configure **Tailscale split DNS** in admin console: `nqlabs.network` → 100.125.207.63
- [x] Validate end-to-end: argocd.platform.nqlabs.network resolves and serves HTTPS
- [x] Document DNS architecture in `docs/decisions/dns-architecture.md`

---

### Problem: Storage

Persistent storage for stateful workloads.

**Tasks (Phase 0 — single node):**
- [x] Install **local-path-provisioner** (Rancher) as default StorageClass
- [x] Validate: PVC creation works, pods mount volumes correctly

**Tasks (distributed storage target — buildable on desktop when storage is allocated):**
- [ ] Evaluate Longhorn vs Rook/Ceph for distributed storage
  - **Longhorn**: simpler, K8s-native, good UI, adequate for home lab
  - **Rook/Ceph**: more powerful, more complex, better for production-grade needs
- [ ] Define storage classes (fast-local, distributed-replicated, etc.)

---

### Problem: Certificate Management

TLS everywhere. No self-signed exceptions in production paths.

**Public DNS provider: Cloudflare**

`nqlabs.network` is the owned private/platform/server domain. It stays
Tailscale/private-network reachable, but uses Let's Encrypt DNS-01 through Cloudflare
so browsers trust HTTPS without installing the NQLabs internal CA. Public `.io`
public service exposure is deferred until the deliberate public-edge design, which can be rehearsed on desktop before NUCs.

Requires a scoped Cloudflare API token stored in 1Password.

**Tasks:**
- [x] Create scoped Cloudflare API token → store in 1Password (`cloudflare-dns-token`)
- [x] Install **cert-manager** via ArgoCD — v1.20.2
- [x] Configure **ClusterIssuer for Let's Encrypt** (DNS-01 via Cloudflare)
- [x] Configure **internal CA** fallback — NQLabs Internal CA (self-signed, 10yr)
- [x] Issue publicly trusted wildcard certs with Let's Encrypt:
  - `*.platform.nqlabs.network`
  - `*.staging.nqlabs.network`
  - `*.production.nqlabs.network`
- [x] Validate: platform-gateway serves HTTPS with valid Let's Encrypt cert; curl succeeds without `-k`

**Cert strategy:** `nqlabs.network` is the owned private/platform/server domain and uses Let's Encrypt DNS-01 while remaining Tailscale/private-network only. `nqlabs.io` is reserved for public/user-facing endpoints in the deliberate public-edge design, which can be rehearsed on desktop before NUCs.

---

### Problem: Secret Management

Secrets must NEVER be committed to git in plaintext.

**Backend: 1Password SDK provider → future OpenBao**

Nick is on a personal 1Password plan, so 1Password Connect is not available. ESO uses
the 1Password SDK provider with a service account token instead. This keeps secret
values out of git while avoiding a Connect server bootstrap dependency.

**Bootstrap strategy:** For initial cluster secrets (Talos keys, onepassword service
account token), use the `op` CLI/manual bootstrap. Once ESO is healthy, create
ExternalSecrets in git that reference 1Password items/fields.

**Tasks:**
- [x] Install **External Secrets Operator** via ArgoCD — v2.6.0
- [x] 1Password Connect not needed — using **1Password SDK** (service account token, personal plan compatible)
  - Service account token bootstrapped as `onepassword-service-account-token` secret in `external-secrets` ns
- [x] Create `ClusterSecretStore` — `nqlabs-1password` (onepasswordSDK provider, vault: NQLabs)
- [x] Migrate Tailscale OAuth to ExternalSecret — `tailscale-operator-oauth` (SecretSynced: True)
- [x] Validate: ExternalSecret resources sync correctly — operator-oauth secret owned by ESO
- [x] Document secret management patterns in `docs/runbooks/secrets.md`
- [ ] Future (Phase 2): migrate to **OpenBao** (self-hosted Vault fork)

---

### Problem: Tailscale Integration

Tailscale is the access layer for `nqlabs.network` services.

**Tasks:**
- [x] Install **Tailscale Operator** for Kubernetes — v1.98.4
- [x] Configure Tailscale subnet router — Connector advertises 192.168.64.0/24 to tailnet
- [x] Define which services are Tailscale-exposed vs gateway-exposed
- [x] Validate: argocd.platform.nqlabs.network reachable over Tailscale with HTTPS

---

### Problem: Observability — Metrics and Dashboards

**Tasks:**
- [x] Install **kube-prometheus-stack** via ArgoCD (includes Prometheus + Grafana + Alertmanager)
- [x] Configure Grafana HTTPRoute at `grafana.platform.nqlabs.network`
- [x] Expose Prometheus at `prometheus.platform.nqlabs.network`
- [x] Expose Alertmanager at `alertmanager.platform.nqlabs.network`
- [x] Import core dashboards: node resources, Kubernetes cluster, Cilium/Hubble (chart defaults)
- [x] Configure Alertmanager with Discord notification channel
  - Webhook stored in 1Password item `alertmanager-discord`, field `webhook_url`
  - Delivery validated with synthetic `NQLabsDiscordTest` alert
- [x] Validate: metrics stack pods Running and HTTPS endpoints responding

---

### Problem: Observability — Logging

**Tasks:**
- [x] Install **Loki** + **Promtail** via ArgoCD (Promtail ships logs from all nodes)
- [x] Configure Grafana as Loki datasource
- [x] Validate: cluster and application logs queryable in Grafana
  - Loki query validated: `{namespace="argocd"}` returns ArgoCD logs

---

### Problem: Progressive Delivery and ArgoCD Boundaries

**Tasks:**
- [x] Install **Argo Rollouts** via ArgoCD
  - Controller and read-only dashboard deployed in `argo-rollouts`
  - Dashboard exposed at `rollouts.platform.nqlabs.network`
  - Rollout/Analysis/Experiment CRDs installed
- [x] Create ArgoCD **AppProjects** before service factory work
  - `platform` — current infrastructure and platform Applications
  - `services-staging` — future staging service Applications, no cluster-scoped resources
  - `services-production` — future production service Applications, no cluster-scoped resources
- [x] Migrate existing platform Applications from `default` to `platform`
- [x] Validate: all ArgoCD Applications `Synced/Healthy`

---

### Problem: Observability — Uptime / Health

**Tasks:**
- [x] Install **Prometheus Blackbox Exporter** for endpoint health checks
- [x] Define health checks for platform-facing and demo service endpoints
  - ArgoCD, Grafana, Prometheus, Alertmanager, Rollouts
  - demo staging and demo production
- [x] Add alerts for endpoint down, endpoint slow, and TLS expiry
- [ ] Add external/client-side probe location for true user-path monitoring
- [ ] Add Uptime Kuma as a human-friendly status dashboard

---

## Phase 0 Completion Backlog

These items are not discarded. They are the remaining work between “operationally
live on the Mac lab” and “complete foundation by the platform readiness definition.”

Immediate next focus:

```text
external/client-side endpoint probing
  → Uptime Kuma status dashboard
  → GitHub repository rules / branch protection
  → multi-cluster namespace strategy finalization
```

- [x] Promote/test demo release path in production, not only staging
      - PR #2 updated `apps/demo/environments/production.yaml`
      - Production now runs `ghcr.io/nicolasqueiroga/nqlabs-demo:sha-aec3a454e4aa`
      - `https://demo.production.nqlabs.network` serves the NQLabs demo HTML
- [x] Add `imagePullSecrets` support to `charts/nqlabs-service` for private registries
      - Supported for both Deployment and Argo Rollouts Rollout pod specs
- [x] Define Terraform `service`/`product` module that writes environment files or opens a PR
      - [x] Add `terraform/modules/nqlabs-service` to generate service environment files
      - [x] Add `terraform/services/demo` definition mirroring the validated demo service
      - [x] Validate with OpenTofu CLI (`fmt`, `init`, `validate`, `plan`, `apply`)
- [ ] Add per-service RBAC, ResourceQuota, LimitRange, and isolation templates
      - [x] Chart renders ResourceQuota, LimitRange, Role, RoleBinding, and CiliumNetworkPolicy
      - [x] Terraform module can generate isolation values
      - [x] Services AppProjects allow the required namespace-scoped resource kinds
      - [x] Mac lab namespace strategy: `<service>-staging` / `<service>-production`
      - [ ] Multi-cluster namespace strategy: same service namespace name in separate staging/production clusters
- [ ] Add external/client-side endpoint probing
- [x] Add Uptime Kuma status dashboard
- [ ] Add full GitHub Actions/repository rules/branch protection plan and implementation
- [ ] Define final multi-repo application delivery model
      - Application/product code lives in app-owned repositories, not this platform repo
      - App repo GitHub Actions builds/publishes images and triggers the ArgoCD delivery path
      - Platform repo keeps only infra/SRE/architecture/reusable platform components
      - After model is proven, clean/migrate temporary `apps/` and `services/` demo material
- [ ] Add public `nqlabs.io` service exposure path during the deliberate public-edge design

---

## Phase 0.7 — Fixed-IP Desktop Full Architecture

Nick may move the whole NQLabs lab from the Mac laptop to a desktop with a fixed IP
before the NUCs are installed. Actual active desktop resources: AMD Ryzen 9 7950X,
124GB RAM, 223.6GB Proxmox system SSD with 130.3GB `local-lvm` thin storage for VM
disks. A separate 1.9TB NTFS SSD is present but not assigned to Proxmox and must not
be repurposed without an explicit decision. Treat this as the virtualized rehearsal
of the full target architecture: more stable than the laptop lab, and capable of running
the management/staging/production cluster topology plus security/operations layers
as VMs before NUCs are added as bare-metal capacity, as long as disks are sized deliberately.

The goal is not to redesign the platform. The goal is to prove that the same GitOps
stack and operating model can move from an ephemeral laptop network to a stable host
network without losing reproducibility. The Mac remains the development/control
workstation; the desktop becomes the always-on infrastructure host.

- [x] Document desktop host fixed IP and network topology
      - Runbook: `docs/runbooks/desktop-lab-bootstrap.md`
- [x] Install/configure desktop as a hypervisor host, preferably Proxmox VE, for Talos VM clusters
- [x] Define desktop VM/runtime subnet and Cilium LoadBalancer pool
- [x] Define desktop Gateway IP, DNS path, and Tailscale routes
- [ ] Run lean desktop VM disks on `local-lvm`; defer heavy storage/data-platform work until storage expansion or explicit 1.9TB SSD repurpose
- [x] Port Talos/bootstrap procedure from Mac UTM assumptions to desktop assumptions
- [x] Bootstrap one `nqlabs-desktop-lab` Talos cluster first to validate Proxmox, Talos, Cilium, DNS, TLS, and GitOps substrate
- [ ] Rehearse the final three-cluster topology as Talos VMs: `nqlabs-management`, `nqlabs-staging`, `nqlabs-production`
      - [x] Add cluster folder scaffolds and initial VM/IP inventory
      - [x] Create/bootstrap `nqlabs-management`
      - [x] Install/validate Gateway API CRDs + Cilium baseline on `nqlabs-management`
      - [ ] Create/bootstrap `nqlabs-staging`
      - [ ] Create/bootstrap `nqlabs-production`
      - [x] Install/bootstrap ArgoCD on `nqlabs-management` without applying desktop-lab root
      - [x] Create/apply constrained management ArgoCD root (`projects.yaml` + `argocd.yaml`)
      - [x] Add `local-path-provisioner` to management root and validate default StorageClass
      - [x] Install External Secrets Operator on management and validate `nqlabs-1password` ClusterSecretStore
      - [x] Install cert-manager on management and validate Cloudflare ExternalSecret + ClusterIssuers
      - [x] Install management DNS stack and validate CoreDNS LB `192.168.15.194`
      - [ ] Expand cluster-aware management ArgoCD app model beyond safe bootstrap apps
      - [ ] Configure management ArgoCD to manage staging/production clusters
- [x] Re-run full ArgoCD app-of-apps bootstrap on desktop lab
- [ ] Re-run app-of-apps bootstrap / cluster registration for the multi-cluster desktop topology
- [x] Validate DNS, Gateway, TLS, service factory, Blackbox probes, Discord alerts, release automation, and Uptime Kuma on desktop-lab
- [ ] Validate DNS, Gateway, TLS, service factory, probes, alerts, and release automation across the three-cluster desktop topology
- [ ] Document differences between Mac lab and desktop lab

---


### Problem: Repository cleanup after architecture completion

The current repository contains some bootstrap/demo application material so the
service factory, release workflow, and monitoring can be validated end-to-end. That
is acceptable during platform construction, but it is not the final ownership model.

Target final state:

- `nqlabs-platform` contains architecture, SRE/infrastructure, cluster lifecycle,
  reusable charts/modules, policies, docs, runbooks, guides, and bootstrap scripts.
- Real applications live in their own repositories.
- Application repositories own source code, Dockerfiles, tests, and GitHub Actions.
- Application repository workflows build/publish images and trigger the ArgoCD/GitOps
  delivery path.
- Temporary in-repo demo app code and contracts are removed, migrated, or explicitly
  labeled as examples/templates.

**Tasks:**
- [x] Create private external demo app repo `NicolasQueiroga/nqlabs-demo` with GitHub Actions enabled and read/write workflow permissions.
- [ ] Decide exact ArgoCD source-of-truth model for external app repositories.
- [ ] Migrate `services/demo` to `NicolasQueiroga/nqlabs-demo` or relabel it as
      a minimal platform example.
- [ ] Remove or migrate `apps/demo` contracts if final service state lives in app repos.
- [ ] Update Terraform/OpenTofu onboarding to create external-repo registration data,
      not permanent app manifests inside the platform repo unless intentionally chosen.
- [ ] Update docs/runbooks/guides after cleanup so the repo structure matches reality.

---

## Phase 1 — Hardware Node Expansion / NUC Addition

Builds on the fixed-IP desktop full architecture. Phase 1 must not introduce new
platform capabilities. Its job is to add NUC-class bare-metal nodes/capacity to the
already-built `nqlabs-management`, `nqlabs-staging`, and `nqlabs-production`
clusters, or to replace Proxmox VM nodes with bare-metal nodes after validation.

Target topology remains:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```

If the NUC pool has 18 machines, a possible node allocation across the existing clusters is:

```text
nqlabs-management: 3 nodes
nqlabs-staging:    6 nodes
nqlabs-production: 9 nodes
```

### Problem: Hardware Planning

- [ ] Define whether each NUC joins an existing cluster as a new node or replaces a VM node
- [ ] Assign static IPs or DHCP reservations for each NUC
- [ ] Document hardware inventory: hostname, MAC address, IP, role, target cluster
- [ ] Define naming convention for nodes (e.g. `nuc-01.infra.nqlabs.network`)
- [ ] Document how to add NUCs to existing Talos clusters
- [ ] Document how to drain/remove Proxmox VM nodes after bare-metal replacement

### Problem: Network Infrastructure

- [ ] Procure managed switch
- [ ] Define VLAN layout:
  - Management VLAN (Talos API, IPMI if available)
  - Cluster VLAN (pod traffic)
  - Storage VLAN (if separate storage network)
  - Services VLAN (LB IPs, ingress)
- [ ] Configure router: DHCP reservations, routing between VLANs
- [ ] Document network diagram

### Problem: Talos on Bare Metal

- [ ] Reuse the existing cluster secrets/config generation model for each target cluster
- [ ] Generate machine configs for NUC nodes using the target cluster secrets
- [ ] Flash/install Talos onto NUCs (USB first, PXE/iPXE later)
- [ ] Join NUCs to the existing management/staging/production clusters as intended
- [ ] Validate mixed Proxmox VM + bare-metal node health during transition
- [ ] Drain/remove VM nodes only after bare-metal nodes are healthy

### Problem: Network-Based Provisioning (L4)

- [ ] Set up PXE/iPXE server (or use Sidero Metal / Omni for Talos)
- [ ] Automate Talos image serving over network
- [ ] Test: plug in bare NUC → boots → installs Talos → joins cluster

---

## Phase 2 — Operations and Security Hardening

Phase 2 capabilities are not NUC-gated. Build them on the desktop after the
management/staging/production baseline is stable, then carry them forward as NUCs
are added as nodes/capacity.

### Problem: Distributed Storage

Storage decision: **Rook/Ceph** (not Longhorn).
Longhorn is easier to start but migration from Longhorn to Ceph is high-complexity.
Distributed storage should be designed and rehearsed on desktop once enough disk is
allocated (for example after repurposing the 1.9TB SSD or adding dedicated virtual
disks). NUCs later add physical disks/capacity; they are not the first moment the
storage architecture can exist. Start with Ceph and avoid a Longhorn→Ceph migration.

- [ ] On desktop: allocate dedicated virtual disks or repurpose the 1.9TB SSD before serious Ceph testing
- [ ] On NUCs later: dedicate storage disk(s) on each NUC (separate from OS disk — minimum 3 nodes for Ceph replication)
- [ ] Install **Rook/Ceph** via ArgoCD
- [ ] Define StorageClasses: `ceph-block` (RWO), `ceph-filesystem` (RWX), `ceph-bucket` (S3-compatible object storage)
- [ ] Validate replication, PVC creation, and failover
- [ ] Configure Ceph dashboard access via Gateway API

### Problem: Backup and Disaster Recovery

- [ ] Install **Velero** for workload backup
- [ ] Configure backup destination (S3-compatible: Backblaze B2, MinIO, or AWS S3)
- [ ] Define backup schedules for all stateful workloads
- [ ] Test restore procedure (this is mandatory — unverified backups are not backups)
- [ ] Document DR runbook


### Problem: Cluster Lifecycle Management (L6)

- [ ] Evaluate Cluster API or Talos Omni for cluster lifecycle
- [ ] Define cluster-as-code: declarative cluster specs in git

### Problem: Identity and SSO

- [ ] Deploy **Authentik** or **Keycloak** as identity provider
- [ ] Configure OIDC for ArgoCD, Grafana, and other platform UIs
- [ ] Define RBAC across the platform

### Problem: Workload Identity

- [ ] Evaluate SPIFFE/SPIRE for workload identity
- [ ] Configure service-to-service mTLS where applicable

### Problem: Internal Developer Platform (IDP)

Goal: define a new product in Terraform → staging + production environments
provisioned automatically, with DNS, TLS, RBAC, and ArgoCD sync — no manual steps.

**Phase 0 (namespace-based, single cluster):**
- [x] Define reusable Helm chart: `charts/nqlabs-service`
      - Supports Deployment or Argo Rollouts `Rollout`
      - Creates Service + optional Gateway API HTTPRoute
- [x] Define environment contract:
      `apps/<service>/environments/{staging,production}.yaml`
- [x] Define ArgoCD **ApplicationSet** — generates one Application per service × environment
      from `apps/*/environments/*.yaml`
- [x] Define namespace lifecycle for Mac lab service-environment namespaces
      - Generated service Applications use `CreateNamespace=true`
      - Service AppProjects allow only `*-staging` and `*-production` destinations in the Mac lab
- [x] Wire external-dns + Gateway API HTTPRoute:
      `<service>.<env>.nqlabs.network` created automatically in the private platform network
- [x] Validate with demo service:
      - `demo.staging.nqlabs.network`
      - `demo.production.nqlabs.network`
- [x] Add GitHub Actions release flow: build/push app image, then PR updating the env value file image tag
      - Workflow: `.github/workflows/release-service.yaml`
      - Helper: `scripts/update-service-image.py`
      - Demo image source: `services/demo/`
      - Builds `linux/amd64` and `linux/arm64` images to GHCR
- [x] Validate release automation against production
      - `demo-production` rolled from `traefik/whoami` to GHCR NQLabs demo image
- [x] Add `imagePullSecrets` support for private image registries
- [x] Define Terraform `service`/`product` module that writes environment files or opens a PR
      - Module and demo definition added
      - OpenTofu validation and local-file apply succeeded without changing existing demo env files
- [ ] Add per-service RBAC, ResourceQuota, LimitRange, and isolation templates
      - [x] Chart and Terraform templates added using CiliumNetworkPolicy
      - [x] Mac lab uses service-environment namespaces for true namespace-scoped quotas
      - [ ] Multi-cluster service namespace model still required for final staging/production separation
- [ ] Harden `charts/nqlabs-service` into an operational service contract
      - Current state: the chart can create and deploy a service automatically
      - Target state: the chart can create an operational, observable, secure service automatically
      - [ ] Add `values.schema.json` for Helm values validation
      - [ ] Add liveness/readiness/startup probe values and templates
      - [ ] Add secure default `podSecurityContext` and container `securityContext`, with documented overrides
      - [ ] Add `ServiceMonitor` support for service metrics scraping
      - [ ] Add `ExternalSecret` support for service secret materialization from 1Password/ESO
      - [ ] Add `PodDisruptionBudget` support
      - [ ] Add `HorizontalPodAutoscaler` support, disabled by default until `metrics-server` or another metrics API exists
      - [ ] Evolve single `route` into internal/public route schema; keep public `.io` disabled until public edge exists
      - [ ] Add chart rendering and policy validation in CI
      - [ ] Add external app repository release example that triggers the ArgoCD delivery path without making app code part of `nqlabs-platform`

**Multi-cluster target (cluster-based, true isolation):**
- [ ] Define `nqlabs-management`, `nqlabs-staging`, and `nqlabs-production` clusters
- [ ] Configure ArgoCD multi-cluster management
- [ ] Update Terraform `product` module to target staging cluster vs production cluster
- [ ] Define shared platform services vs per-cluster services

### Problem: Policy Enforcement

- [ ] Install **Kyverno** in audit mode first — observe without blocking
- [ ] Define core policies: resource limits required, no privileged containers,
      approved image registries, labels required on all workloads
- [ ] Graduate policies from audit → enforce incrementally
- [ ] Define Kyverno ClusterPolicies in git, managed by ArgoCD

### Problem: Runtime Security

- [ ] Install **Falco** (eBPF driver, no kernel module required on Talos)
- [ ] Configure Falco rules for anomaly detection (syscall-level)
- [ ] Route Falco alerts to Alertmanager → notification channels
- [ ] Validate: simulate a suspicious syscall and verify alert fires

### Problem: Secrets Backend Migration

- [ ] Deploy **OpenBao** (self-hosted, OSS successor to HashiCorp Vault)
- [ ] Migrate all secrets from 1Password SDK/1Password vault to OpenBao
- [ ] Update ClusterSecretStore in External Secrets Operator to point to OpenBao
- [ ] Enable OpenBao PKI backend for internal certificate authority (replaces cert-manager self-signed CA)
- [ ] Define backup and unseal strategy for OpenBao

### Problem: Container Registry

- [ ] Deploy **Harbor** (CNCF graduated OCI registry)
- [ ] Configure proxy cache projects for: Docker Hub, ghcr.io, quay.io, registry.k8s.io
  — workloads continue using upstream image refs; Harbor caches and scans them
- [ ] Configure Harbor as the primary push target for any internal images
- [ ] Enable **Trivy** integration in Harbor for vulnerability scanning on push and schedule
- [ ] Configure Kyverno policy: only admit images pulled through Harbor
- [ ] Expose Harbor at `registry.platform.production.nqlabs.network`

### Problem: Observability — Distributed Tracing

- [ ] Deploy **OpenTelemetry Collector** as the unified collection layer
  — receives traces, metrics, and logs; routes to appropriate backends
- [ ] Deploy **Grafana Tempo** for trace storage
- [ ] Configure Grafana datasource for Tempo
- [ ] Add Tempo as a Grafana datasource alongside Prometheus and Loki
- [ ] Enable trace-to-log and trace-to-metric correlation in Grafana
- [ ] Validate: generate a trace and view it in Grafana

### Problem: Supply Chain Security

- [ ] Integrate **Cosign** for image signing in any internal build pipelines
- [ ] Configure Kyverno policy to verify image signatures for internal images
- [ ] Generate SBOMs (Software Bill of Materials) for internal images
- [ ] Store SBOMs in Harbor alongside images

---

## Open Questions

None. All decisions locked. ✓

---

## Technology Decisions (Locked)

| Layer | Choice | Rationale |
|-------|--------|-----------|
| OS | Talos Linux | Immutable, API-driven, Kubernetes-native |
| Orchestration | Kubernetes (via Talos) | Platform foundation |
| GitOps | ArgoCD | Chosen |
| CNI | Cilium | eBPF, built-in LB IPAM, Hubble, kube-proxy-free |
| Ingress | Cilium Gateway API | Modern Gateway API spec, zero extra components, native to CNI |
| Cert Management | cert-manager + Cloudflare DNS-01 + internal CA fallback | Publicly trusted certs for owned private `.network`; `.io` waits for public edge |
| Secrets Operator | External Secrets Operator | Decouples secrets from manifests |
| Secrets Backend (now) | 1Password SDK provider | Personal-plan compatible; service account token bootstrapped once |
| Secrets Backend (future) | **OpenBao** | Self-hosted OSS Vault fork; after desktop multi-cluster baseline is stable |
| Metrics | kube-prometheus-stack | Standard (Prometheus + Grafana + Alertmanager) |
| Logging | Loki + Promtail | Grafana-native, lightweight |
| VPN/Access | Tailscale + Tailscale Operator | Access layer for all phases |
| Public domain | nqlabs.io | DNS managed by Cloudflare |
| Internal domain | nqlabs.network | Tailscale split DNS throughout all phases |
| DNS provider (external) | Cloudflare | Public DNS delegation for owned domains; DNS-01 validation for `.network` |
| DNS resolver (internal) | Tailscale split DNS → in-cluster CoreDNS ← external-dns | Fully automated; no AdGuard Home needed |
| VM backend (laptop) | UTM | M1 Pro native; ARM64 Talos images |
| Desktop lab host | AMD Ryzen 9 7950X, 124GB RAM, 130GB active Proxmox thin VM storage, fixed IP | Build full architecture now; NUCs later add/replace nodes |
| GitHub repository | Public | No deploy key needed; strict secrets discipline required |
| Laptop architecture | ARM64 (Apple M1 Pro) | Use `metal-arm64` Talos images for local testing |
| NUC node expansion | x86_64 Dell NUC-class node pool | Add bare-metal nodes/capacity to the desktop-proven clusters; use `metal-amd64` Talos images |
| Target cluster topology | `nqlabs-management`, `nqlabs-staging`, `nqlabs-production` | Separates management, staging, and production control planes |
| Storage (Phase 0) | local-path-provisioner | Simple, zero overhead for single node |
| Distributed Storage | **Rook/Ceph** | Production-grade distributed storage; rehearse on desktop when disk is allocated; NUCs add physical capacity later |
| Container Registry | **Harbor** | CNCF graduated; proxy cache for Docker Hub/ghcr.io/quay.io + internal images + Trivy scanning |
| Policy Enforcement | **Kyverno** | Admission control, policy-as-code, image verification |
| Runtime Security | **Falco** | eBPF-based syscall-level anomaly detection |
| Secrets Backend | **OpenBao** | Self-hosted OSS Vault fork; replaces 1Password SDK/1Password vault dependency |
| Tracing | **Grafana Tempo** | Distributed trace storage; pairs with OTel Collector |
| Telemetry Collection | **OpenTelemetry Collector** | Unified collection layer for metrics, logs, traces |
| Supply Chain | **Cosign + Trivy** | Image signing and vulnerability scanning |
| Service network policy | **CiliumNetworkPolicy** | Cilium-native L3/L4/L7/FQDN-capable workload isolation |

---

*Last updated: desktop-lab operationally live on Proxmox — GitOps, DNS, Let's Encrypt TLS for `.network`, Tailscale-only HAProxy edge, secrets, Gateway, metrics, logging, Rollouts, ArgoCD project boundaries, service factory/demo app, Blackbox endpoint probes, Discord alerting, Uptime Kuma, service release automation, production release validation, private image pull support, Terraform service onboarding, and service-environment namespace/CiliumNetworkPolicy isolation scaffolding online. Next architectural target: build `nqlabs-management`, `nqlabs-staging`, and `nqlabs-production` plus security/operations layers on the desktop; NUCs later add/replace nodes in that same architecture.*
