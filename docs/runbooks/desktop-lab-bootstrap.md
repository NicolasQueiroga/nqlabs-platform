# Runbook: Desktop Lab Bootstrap — Proxmox + Talos VMs

Status: active for Phase 0.7. The first desktop Talos cluster is live; the next target is the three-cluster VM rehearsal.

This runbook moves NQLabs from the Mac/UTM proof lab to a stable fixed-IP desktop
host while keeping the Mac as the development and operations workstation.

## Roles

```text
MacBook
  purpose: write code, edit infrastructure, run kubectl/talosctl/gh/op, push to GitHub
  does not: host the durable Kubernetes platform

Desktop
  purpose: always-on infrastructure host
  runs: Proxmox VE or another KVM hypervisor
  hosts: Talos VMs and eventually multi-cluster rehearsals

GitHub
  purpose: GitOps source of truth

ArgoCD on desktop cluster
  purpose: pull from GitHub and reconcile the platform
```

The Mac remains where infrastructure development happens. The desktop is where the
platform runs.

## Target hardware

Current planned desktop:

```text
CPU:     AMD Ryzen 9 7950X
Memory:  124GB usable by Proxmox
Storage: 223.6GB active Proxmox system SSD
         130.3GB local-lvm thin pool for VM disks
         1.9TB secondary SSD present as NTFS, not assigned to Proxmox yet
Network: fixed LAN IP / DHCP reservation
```

The desktop is CPU/RAM-rich but the active Proxmox VM pool is smaller than the
original 2TB assumption. The platform can still rehearse the full final topology if
we are disk-conscious:

- use thin-provisioned VM disks on `local-lvm`
- keep the first bootstrap VM at 96GB thin disk: large enough for the full platform,
  still safe on the 130GB active thin pool if actual usage is monitored
- keep Loki/Prometheus retention short during desktop rehearsal
- do not run real database/storage-platform workloads yet
- do not repurpose the 1.9TB NTFS disk unless Nick explicitly approves wiping it
- if needed later, move VM storage to the 1.9TB disk or add dedicated storage before
  data-platform work

## Recommended approach

Treat the desktop as the place where the full architecture is built first. Start
with one desktop Talos cluster to prove the substrate, then run the final
three-cluster topology as VMs. NUCs later add/replace nodes in this architecture;
do not wait for them to implement platform capabilities.

```text
Step 1: nqlabs-desktop-lab       # one cluster, proves Proxmox + Talos + GitOps migration
Step 2: nqlabs-management        # platform/control services
        nqlabs-staging           # staging workloads
        nqlabs-production        # production workloads
```

Do not debug Proxmox, desktop networking, Talos, Cilium, ArgoCD, DNS, TLS, and
multi-cluster all at once. First prove the desktop substrate with one cluster.
After that substrate is boring, the desktop target is not merely “a better Mac lab”;
it is the full private-cloud architecture. The future NUCs provide bare-metal
capacity and durability for the same clusters.

## Required decisions before install

Fill these values before creating VMs:

| Value | Example | Actual |
|-------|---------|--------|
| Desktop hostname | `nqlabs-desktop` | `nqlabs-desktop.nqlabs.network` |
| Desktop LAN IP | `192.168.1.10` | `192.168.15.20` |
| LAN gateway | `192.168.1.1` | `192.168.15.1` |
| LAN DNS | router / public resolver | `192.168.15.1` |
| Proxmox bridge | `vmbr0` | `vmbr0` → `nic0` |
| Talos node IP range | `192.168.1.20-39` | `192.168.15.30-49` |
| Cilium LB pool | `192.168.1.192/28` | `192.168.15.192/28` |
| Desktop CoreDNS LB IP | `192.168.1.192` | `192.168.15.192` |
| Desktop Gateway LB IP | `192.168.1.193` | `192.168.15.193` |
| Tailscale subnet route | chosen LAN/subnet | `192.168.15.0/24` |

Temporary pre-Kubernetes management DNS:

```text
proxmox.platform.nqlabs.network → 100.105.35.84
```

This is served by a temporary CoreDNS systemd service on Proxmox. Replace Tailscale
split DNS with the Kubernetes CoreDNS Tailscale IP after the desktop cluster is up.

The Mac lab currently uses `192.168.64.0/24` because UTM creates that NAT network.
Do not reuse those addresses on the desktop unless the desktop LAN really uses them.

## Phase A — Prepare from the Mac

On the Mac:

1. Confirm the clean repo is cloned/available:

   ```bash
   cd ~/Documents/home-lab
   git remote -v
   git status
   ```

2. Install/verify tools:

   ```bash
   brew install kubectl helm gh
   brew install siderolabs/tap/talosctl
   talosctl version --client
   kubectl version --client
   helm version
   gh auth status
   ```

3. Download required ISOs/images:

   - Proxmox VE ISO from <https://www.proxmox.com/en/downloads>
   - Talos x86_64 VM/metal image from <https://factory.talos.dev/>

4. Keep secrets out of Git. Talos secrets, kubeconfigs, generated machine configs,
   and Proxmox credentials must go to 1Password, not the repository.

## Phase B — Install Proxmox VE on the desktop

> Warning: installing Proxmox will wipe the target desktop disk. Back up anything
> important first.

1. Create a bootable USB with the Proxmox VE ISO.
2. Boot the desktop from USB.
3. Install Proxmox onto the desktop SSD.
4. Set:

   ```text
   hostname: nqlabs-desktop
   management IP: fixed IP or DHCP-reserved IP
   gateway: LAN router
   DNS: router or trusted resolver
   ```

5. After reboot, open from the Mac:

   ```text
   https://<desktop-ip>:8006
   ```

6. Log in as `root` using the password created during install.
7. Update Proxmox packages from the UI or shell.
8. Confirm bridge networking exists:

   ```text
   Datacenter → node → System → Network → vmbr0
   ```

`vmbr0` should bridge VMs onto the LAN so Talos nodes can get normal LAN IPs.

## Phase B.1 — Host boot and recovery policy

The desktop should try to recover automatically because it is now the always-on
infrastructure host.

Current host values:

```text
hostname:          nqlabs-desktop
LAN IP:            192.168.15.20
Tailscale IP:      100.105.35.84
Ethernet NIC:      nic0
Ethernet MAC:      74:56:3c:f7:32:39
Proxmox bridge:    vmbr0 → nic0
```

Configured on Proxmox:

```text
nqlabs-wol.service
  enables Wake-on-LAN on nic0 at boot

/usr/lib/systemd/system-shutdown/nqlabs-rtc-wake
  on clean poweroff/halt, schedules RTC wake about 5 minutes later
```

Verify:

```bash
ssh root@100.105.35.84 'ethtool nic0 | grep Wake-on; systemctl is-active nqlabs-wol.service'
```

Wake from the Mac if the desktop is powered off but still connected to power and
Ethernet:

```bash
brew install wakeonlan
wakeonlan 74:56:3c:f7:32:39
```

Manual BIOS/UEFI settings still required:

```text
Restore on AC Power Loss: Power On / Always On
Wake on LAN / PCI-E wake: Enabled
ErP: Disabled if it prevents Wake-on-LAN from S5
```

OS-level automation cannot recover from sudden power loss if firmware stays off.
The BIOS AC-power setting is the required guarantee for outage recovery.

## Phase C — Create the first Talos desktop cluster

Create one cluster first:

```text
cluster name: nqlabs-desktop-lab
purpose: prove desktop substrate and GitOps migration
```

Recommended initial VM sizing:

| VM | Role | vCPU | RAM | Disk | Notes |
|----|------|------|-----|------|-------|
| `talos-desktop-cp-01` | control plane + worker | 16 | 64GB | 96GB thin | first large all-in-one desktop cluster |

Planned first VM identity:

```text
VMID:       130
Name:       talos-desktop-cp-01
MAC:        BC:24:11:15:00:30
IP:         192.168.15.30/24
Gateway:    192.168.15.1
DNS:        192.168.15.1, 1.1.1.1
CPU/RAM:    16 vCPU, 64GB RAM
Storage:    local-lvm, 96GB thin disk
Bridge:     vmbr0
Autostart:  enabled after Talos is installed and stable
```

If the first cluster needs more disk later:

```bash
qm resize 130 scsi0 +20G
```

Then grow the filesystem from inside the guest if required. Talos and Kubernetes
usually see the expanded block device, but workload PVC/filesystem expansion still
depends on the storage layer. Do not expand aggressively until the 1.9TB secondary
SSD is explicitly repurposed for Proxmox or additional storage is added.

When the VM exists and is stable, configure Proxmox autostart:

```bash
qm set 130 --onboot 1 --startup order=10,up=120,down=120
```

This makes the first Talos cluster start automatically whenever Proxmox boots.

If you want a more realistic first cluster:

| VM | Role | vCPU | RAM | Disk |
|----|------|------|-----|------|
| `talos-desktop-cp-01` | control plane | 8 | 24GB | 48GB thin |
| `talos-desktop-worker-01` | worker | 8 | 24GB | 48GB thin |
| `talos-desktop-worker-02` | worker | 8 | 24GB | 48GB thin |

Use UEFI, q35 machine type if available, virtio disk, virtio NIC, and bridge to
`vmbr0`.

## Phase D — Generate Talos configs from the Mac

On the Mac, create a desktop cluster directory:

```bash
cd ~/Documents/home-lab
mkdir -p clusters/desktop-lab/{patches,generated}
```

Create a desktop control-plane patch, for example:

```yaml
# clusters/desktop-lab/patches/controlplane.yaml
machine:
  install:
    disk: /dev/vda
cluster:
  allowSchedulingOnControlPlanes: true
```

For a multi-node cluster, only keep `allowSchedulingOnControlPlanes: true` if you
want workloads to run on the control-plane node. For a single-node first cluster,
it is required.

Generate and store Talos secrets:

```bash
talosctl gen secrets -o clusters/desktop-lab/generated/secrets.yaml
```

Immediately store the secrets in 1Password:

```text
Vault: NQLabs
Item: talos-desktop-lab-secrets
```

Then generate configs:

```bash
export TALOS_CP_IP=<desktop-talos-control-plane-ip>

talosctl gen config \
  --with-secrets clusters/desktop-lab/generated/secrets.yaml \
  --config-patch-control-plane @clusters/desktop-lab/patches/controlplane.yaml \
  nqlabs-desktop-lab \
  https://$TALOS_CP_IP:6443 \
  --output-dir clusters/desktop-lab/generated
```

Generated files under `clusters/desktop-lab/generated/` must stay gitignored.

## Phase E — Apply Talos config and bootstrap

Apply config:

```bash
talosctl apply-config \
  --insecure \
  --nodes $TALOS_CP_IP \
  --file clusters/desktop-lab/generated/controlplane.yaml
```

Wait for reboot, then bootstrap etcd exactly once:

```bash
talosctl --talosconfig clusters/desktop-lab/generated/talosconfig \
  --nodes $TALOS_CP_IP \
  --endpoints $TALOS_CP_IP \
  bootstrap
```

Fetch kubeconfig:

```bash
talosctl --talosconfig clusters/desktop-lab/generated/talosconfig \
  --nodes $TALOS_CP_IP \
  --endpoints $TALOS_CP_IP \
  kubeconfig clusters/desktop-lab/generated/kubeconfig

export KUBECONFIG=$PWD/clusters/desktop-lab/generated/kubeconfig
kubectl get nodes
```

## Phase F — Port platform networking values

Before bootstrapping ArgoCD, adjust desktop-specific values in Git:

1. Cilium LB pool:

   ```text
   infrastructure/networking/cilium/lb-ipam/pool.yaml
   ```

   Replace Mac UTM pool with the desktop Cilium LB pool.

2. Cilium L2 announcement interface:

   ```text
   infrastructure/networking/cilium/lb-ipam/l2-announcement.yaml
   ```

   Replace the Mac VM interface (`enp0s1`) if Talos uses a different NIC name on
   Proxmox, commonly `eth0` or `enp6s18` depending on the VM.

3. CoreDNS and Gateway expected IPs:

   ```text
   docs/decisions/ip-address-plan.md
   infrastructure/networking/tailscale/coredns-svc.yaml
   infrastructure/networking/tailscale/platform-gateway-svc.yaml
   ```

4. Tailscale subnet router:

   ```text
   infrastructure/networking/tailscale/subnet-router.yaml
   ```

   Advertise the desktop LAN/subnet or the specific service IP range needed by
   clients.

5. Keep Cloudflare DNS-01 unchanged for `.network`; the domain and token model do
   not change when moving from Mac to desktop.

## Phase G — Bootstrap GitOps on the desktop cluster

From the Mac with the desktop cluster kubeconfig active:

1. Install Cilium and Gateway API CRDs first, following the existing Cilium/Gateway
   docs but using desktop IP values.
2. Install ArgoCD bootstrap manifests.
3. Apply the root app:

   ```bash
   kubectl apply -n argocd -f platform/argocd/apps/root.yaml
   ```

4. Watch reconciliation:

   ```bash
   kubectl get applications -n argocd
   ```

5. Confirm:

   ```text
   root                 Synced / Healthy
   gateway              Synced / Healthy
   cert-manager-config  Synced / Healthy
   external-dns         Synced / Healthy
   service-factory      Synced / Healthy
   demo-staging         Synced / Healthy
   demo-production      Synced / Healthy
   ```

## Phase H — Update Tailscale

### Context

The Mac lab Tailscale devices have been removed. The old CoreDNS split DNS target
(`100.125.207.63`) no longer exists. `*.nqlabs.network` DNS is intentionally broken
until the desktop CoreDNS Service gets its new Tailscale IP and the split DNS entry
is updated.

### Step 1 — Find the new CoreDNS Tailscale IP

After the desktop cluster is up and the Tailscale operator has reconciled, find the
new CoreDNS Tailscale IP:

```bash
kubectl get svc -n dns coredns -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Or check the Tailscale admin console — a new device named `coredns` should appear
with a `100.x.x.x` address.

### Step 2 — Update Tailscale split DNS

In the Tailscale admin console:

```text
https://login.tailscale.com/admin/dns
```

Under **Nameservers**:

1. Remove the old entry:
   ```text
   100.125.207.63  →  nqlabs.network
   ```

2. Add the new entry:
   ```text
   <new-desktop-coredns-tailscale-ip>  →  nqlabs.network
   ```

3. Save.

### Step 3 — Approve subnet route

In the Tailscale admin console under **Machines**, find the desktop subnet router
and approve the advertised route for the desktop LAN/Cilium LB range.

### Step 4 — Verify from Mac and iPhone

```bash
dig argocd.platform.nqlabs.network +short
curl https://argocd.platform.nqlabs.network
curl https://demo.staging.nqlabs.network
curl https://demo.production.nqlabs.network
```

Expected results:

```text
DNS returns the desktop Gateway IP
HTTPS succeeds without certificate warnings
```

If DNS does not resolve, check:

```bash
# Confirm split DNS is active on the Mac
scutil --dns | grep -A5 nqlabs.network

# Test directly against the new CoreDNS IP
dig argocd.platform.nqlabs.network @<new-desktop-coredns-tailscale-ip>
```

## Phase I — Rehearse the full topology in desktop VMs

The desktop is powerful enough to run the full target architecture now. NUCs are
later bare-metal node/capacity expansion, not a blocker for multi-cluster design or
Phase 2 security/operations capabilities.

Target clusters:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```

Initial lean VM sizing on 124GB RAM and 130GB active `local-lvm` thin storage:

| Cluster | VMID | VM | IP | Initial sizing | Purpose |
|---------|------|----|----|----------------|---------|
| `nqlabs-management` | `131` | `talos-management-cp-01` / `BC:24:11:15:00:31` | `192.168.15.31` | 8 vCPU / 32GB RAM / 48GB thin | ArgoCD, DNS, shared platform tools |
| `nqlabs-staging` | `132` | `talos-staging-cp-01` | `192.168.15.32` | 8 vCPU / 24GB RAM / 32GB thin | staging workloads |
| `nqlabs-production` | `133` | `talos-production-cp-01` | `192.168.15.33` | 12 vCPU / 40GB RAM / 48GB thin | production workloads |

This is the max recommended CPU/RAM profile for the desktop before repurposing the
1.9TB SSD. It uses 28 vCPU and 96GB RAM across the three target clusters, leaving
headroom for Proxmox and host services on a 32-thread / 124GB system.

It also declares 128GB of thin VM disks. Thin allocation means actual storage starts
lower, but disk usage must be watched because the active thin pool is about 130GB.
The existing `desktop-lab` VM 130 is a temporary substrate proof; once the
management/staging/production topology takes over, either stop/reduce VM 130 or move
VM storage to the 1.9TB SSD before adding storage-heavy platform services or long
observability retention.

### Phase I.1 — Prepare cluster folders and inventory

Each target cluster gets a folder under `clusters/`:

```text
clusters/nqlabs-management/
clusters/nqlabs-staging/
clusters/nqlabs-production/
```

Each folder documents VMID, IP, endpoint, purpose, and generated-file handling.
Generated secrets/configs must remain under `generated/` and in 1Password.

### Phase I.2 — Bootstrap order

Do not create all clusters simultaneously. Build and validate one at a time:

1. `nqlabs-management`
2. `nqlabs-staging`
3. `nqlabs-production`

For each cluster:

1. Create the Proxmox VM.
2. Generate Talos secrets and machine configs from the Mac.
3. Store Talos secrets in 1Password.
4. Apply Talos config and bootstrap Kubernetes.
5. Install Gateway API CRDs and Cilium.
6. Validate node Ready, pod networking, DNS, and Cilium health.
7. Only then proceed to the next cluster.

Detailed lifecycle: `docs/runbooks/cluster-lifecycle.md`.

### Phase I.3 — Multi-cluster ingress model

Keep the Tailscale-only external edge on Proxmox:

```text
client on tailnet
  -> *.nqlabs.network resolves to 100.105.35.84
  -> HAProxy on Proxmox tailscale0
  -> SNI routes to the correct cluster Gateway
```

Initial Gateway allocation:

| Hostname pattern | Cluster | Planned Gateway IP |
|------------------|---------|--------------------|
| `*.platform.nqlabs.network` | `nqlabs-management` | `192.168.15.195` |
| `*.staging.nqlabs.network` | `nqlabs-staging` | `192.168.15.196` |
| `*.production.nqlabs.network` | `nqlabs-production` | `192.168.15.197` |

Current desktop-lab HAProxy forwards all HTTP(S) traffic to the single desktop-lab
Gateway at `192.168.15.193`. During multi-cluster migration, change HAProxy from a
single backend to SNI-based backends only after each target cluster Gateway is live.

### Phase I.4 — GitOps model

Final rehearsal target:

- `nqlabs-management` runs ArgoCD and platform/control services.
- `nqlabs-staging` and `nqlabs-production` are registered to management ArgoCD.
- Staging service Applications target the staging cluster.
- Production service Applications target the production cluster.
- Service namespaces become `namespace/<service>` in each environment cluster, not
  `<service>-staging` and `<service>-production` inside one cluster.

Do not migrate workloads to multi-cluster GitOps until management ArgoCD can see all
clusters and the service ApplicationSet has explicit cluster destinations.

## Success criteria

Desktop Phase 0.7 is successful when:

- The Mac can administer the desktop cluster with `kubectl` and `talosctl`.
- ArgoCD reconciles the platform from GitHub on the desktop cluster.
- `*.platform.nqlabs.network`, `*.staging.nqlabs.network`, and
  `*.production.nqlabs.network` resolve through Tailscale/CoreDNS.
- Gateway serves Let's Encrypt certificates for `.network` without browser warnings.
- Demo staging and production are reachable.
- Monitoring, logging, Blackbox probes, and Discord alerts are healthy.
- The Mac can be rebooted/sleep without killing the platform.
- The desktop has either completed or is ready to begin the VM-based
  `nqlabs-management` / `nqlabs-staging` / `nqlabs-production` rehearsal.

## Rollback strategy

Keep the Mac/UTM lab untouched until the desktop lab is verified.

If desktop bootstrap fails:

1. Keep using the Mac cluster.
2. Revert any unmerged desktop-specific IP changes.
3. Fix the desktop runbook/IP plan.
4. Retry from a clean Talos VM.
