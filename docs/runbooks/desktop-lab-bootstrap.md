# Runbook: Desktop Lab Bootstrap — Proxmox + Talos VMs

Status: planned for Phase 0.7.

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
Memory:  128GB RAM
Storage: 2TB SSD
Network: fixed LAN IP / DHCP reservation
```

## Recommended approach

Treat the desktop as the virtualized NUC architecture rehearsal. Start with one
desktop Talos cluster first to prove the substrate, then run the final three-cluster
topology as VMs.

```text
Step 1: nqlabs-desktop-lab       # one cluster, proves Proxmox + Talos + GitOps migration
Step 2: nqlabs-management        # platform/control services
        nqlabs-staging           # staging workloads
        nqlabs-production        # production workloads
```

Do not debug Proxmox, desktop networking, Talos, Cilium, ArgoCD, DNS, TLS, and
multi-cluster all at once. First prove the desktop substrate with one cluster.
After that substrate is boring, the desktop target is not merely “a better Mac lab”;
it is the full virtualized version of the future NUC private cloud.

## Required decisions before install

Fill these values before creating VMs:

| Value | Example | Actual |
|-------|---------|--------|
| Desktop hostname | `nqlabs-desktop` | TBD |
| Desktop LAN IP | `192.168.1.10` | TBD |
| LAN gateway | `192.168.1.1` | TBD |
| LAN DNS | router / public resolver | TBD |
| Proxmox bridge | `vmbr0` | TBD |
| Talos node IP range | `192.168.1.20-39` | TBD |
| Cilium LB pool | `192.168.1.200-220` | TBD |
| Desktop CoreDNS LB IP | `192.168.1.200` | TBD |
| Desktop Gateway LB IP | `192.168.1.201` | TBD |
| Tailscale subnet route | chosen LAN/subnet | TBD |

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

## Phase C — Create the first Talos desktop cluster

Create one cluster first:

```text
cluster name: nqlabs-desktop-lab
purpose: prove desktop substrate and GitOps migration
```

Recommended initial VM sizing:

| VM | Role | vCPU | RAM | Disk | Notes |
|----|------|------|-----|------|-------|
| `talos-desktop-cp-01` | control plane + worker | 4 | 8-12GB | 80GB | first single-node cluster |

If you want a more realistic first cluster:

| VM | Role | vCPU | RAM | Disk |
|----|------|------|-----|------|
| `talos-desktop-cp-01` | control plane | 4 | 8GB | 80GB |
| `talos-desktop-worker-01` | worker | 4 | 8GB | 80GB |
| `talos-desktop-worker-02` | worker | 4 | 8GB | 80GB |

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

In Tailscale admin DNS settings, keep:

```text
nqlabs.network → CoreDNS tailnet IP
```

But the CoreDNS tailnet IP will change if the desktop cluster creates a new
Tailscale-exposed CoreDNS Service.

Also approve the desktop subnet route advertised by the desktop subnet router.

Expected checks from the Mac and iPhone:

```bash
dig argocd.platform.nqlabs.network +short
curl https://argocd.platform.nqlabs.network
curl https://demo.staging.nqlabs.network
curl https://demo.production.nqlabs.network
```

Expected results:

```text
DNS returns desktop Gateway IP
HTTPS succeeds without certificate warnings
```

## Phase I — Rehearse the NUC topology in VMs

Only after the single desktop cluster is boring, rehearse the same target topology
that will later move to NUC bare metal:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```

Suggested VM sizing on 128GB RAM:

| Cluster | Initial VMs | Purpose |
|---------|-------------|---------|
| `nqlabs-management` | 1-3 VMs | ArgoCD, monitoring, DNS, shared platform tools |
| `nqlabs-staging` | 1-2 VMs | staging app workloads |
| `nqlabs-production` | 1-2 VMs | production app workloads |

Do not over-allocate at first. Prove the lifecycle and GitOps model, then scale VM
counts. The desktop rehearsal should answer the architecture questions before the
NUCs exist: multi-cluster ArgoCD, cluster-specific AppProjects/destinations,
staging/production separation by control plane, shared management services, and
cross-cluster operational workflows.

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
