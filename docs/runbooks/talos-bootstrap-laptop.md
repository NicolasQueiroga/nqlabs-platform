# Runbook: Talos Bootstrap — Laptop (UTM / ARM64)

**Target**: Single-node Talos cluster on MacBook Pro M1 via UTM
**Talos version**: v1.13.3
**Architecture**: ARM64 (native UTM VM)
**Networking**: UTM Shared Network (NAT) + Tailscale for access

---

## Prerequisites

All of these must be done before starting.

| Tool | Install | Verify |
|------|---------|--------|
| `talosctl` | `brew install siderolabs/tap/talosctl` | `talosctl version --client` |
| `kubectl` | `brew install kubectl` | `kubectl version --client` |
| `helm` | `brew install helm` | `helm version` |
| UTM | Already installed | Open UTM.app |
| Talos ISO | `~/Downloads/talos/metal-arm64-v1.13.3.iso` | `ls ~/Downloads/talos/` |

---

## Step 1 — Create the UTM Virtual Machine

1. Open **UTM.app**
2. Click **Create a New Virtual Machine**
3. Select **Virtualize** (not Emulate — we want native ARM64 speed)
4. Select **Other**
5. On "Boot ISO Image": click **Browse** → select `~/Downloads/talos/metal-arm64-v1.13.3.iso`
6. Hardware settings:
   - **CPU Cores**: 4
   - **Memory**: 6144 MB (6 GB)
7. Storage: **50 GB** (leave default path)
8. Shared Directory: **skip** (not needed)
9. Summary — Name: `talos-lab` → **Save**

### Network configuration (important)

After the VM is created, before starting it:

1. Select the VM → click **Edit** (pencil icon)
2. Go to **Network**
3. Set **Network Mode** to **Shared Network**
4. Note the **Guest Network** CIDR shown (typically `192.168.64.0/24`)
5. Save

> Shared Network (NAT) gives the VM an IP in the `192.168.64.x` range reachable
> from the Mac. The Mac's host IP on that interface is `192.168.64.1`.

---

## Step 2 — Boot into Talos Maintenance Mode

1. Start the `talos-lab` VM in UTM
2. UTM may show **"Display output is not active"** — this is normal. Talos is headless.
3. The VM will get an IP via DHCP from UTM's shared network (`192.168.64.x`)

Find the IP from your Mac terminal:
```bash
arp -a | grep "192.168.64"
# Expected: 192.168.64.1 (UTM gateway) and one VM IP such as 192.168.64.3
```

Set it in your shell (do not commit this):
```bash
export TALOS_IP=192.168.64.3   # adjust if different
```

Verify Talos is reachable in maintenance mode:
```bash
talosctl get disks --insecure --nodes $TALOS_IP
# Should list: loop0, sr0 (CD-ROM), vda (install target)
```

---

## Step 3 — Generate Cluster Secrets

> **These secrets must NEVER be committed to git.**
> Store them in 1Password immediately after generation.

```bash
cd ~/Documents/home-lab

# Generate secrets file
talosctl gen secrets -o secrets.yaml
```

Immediately save `secrets.yaml` to 1Password:
- Vault: `NQLabs`
- Item name: `talos-lab-secrets`
- Attach the file or paste the contents

Verify it is gitignored:
```bash
git status  # secrets.yaml must NOT appear here
```

---

## Step 4 — Generate Machine Configuration

```bash
cd ~/Documents/home-lab

# Generate configs for the lab cluster
talosctl gen config \
  --with-secrets secrets.yaml \
  --config-patch-control-plane @clusters/lab/patches/controlplane.yaml \
  nqlabs-lab \
  https://$TALOS_IP:6443 \
  --output-dir clusters/lab/generated
```

> The `--config-patch-control-plane` flag applies the patch that allows workloads
> to run on the control plane node (required for single-node setup).

This creates:
- `clusters/lab/generated/controlplane.yaml` — the machine config (gitignored)
- `clusters/lab/generated/worker.yaml` — not used for single-node (gitignored)
- `clusters/lab/generated/talosconfig` — your talosctl context (gitignored)

---

## Step 5 — Apply Configuration

```bash
# Apply the control plane config to the node
talosctl apply-config \
  --insecure \
  --nodes $TALOS_IP \
  --file clusters/lab/generated/controlplane.yaml
```

The response will say "Applied configuration without a reboot" — this is normal.
Talos schedules the disk installation and reboots asynchronously.

Wait ~60 seconds then verify the cert changed from maintenance to configured:
```bash
echo | openssl s_client -connect $TALOS_IP:50000 2>&1 | grep "CN="
# Maintenance mode:  CN=maintenance-service.talos.dev
# Configured node:   CN=talos-XXXX-XXX  (random hostname)
```

If the cert is still `maintenance-service.talos.dev` after 60s, the install disk
may not have been found. Verify `clusters/lab/patches/controlplane.yaml` has
`machine.install.disk: /dev/vda` set correctly.

---

## Step 6 — Bootstrap etcd

This is done **exactly once** per cluster. Never run again.

> **Important:** Always include `--endpoints` when using the talosconfig.
> The generated talosconfig has `endpoints: []` and requires it to be passed explicitly.

```bash
talosctl --talosconfig clusters/lab/generated/talosconfig \
  --endpoints $TALOS_IP \
  --nodes $TALOS_IP \
  bootstrap
```

Wait ~30 seconds, then retrieve kubeconfig.

---

## Step 7 — Get Kubeconfig

```bash
talosctl --talosconfig clusters/lab/generated/talosconfig \
  --endpoints $TALOS_IP \
  --nodes $TALOS_IP \
  kubeconfig ~/.kube/config --force
```

---

## Step 8 — Install Cilium CNI

The node will be `NotReady` until a CNI is installed. Install Cilium immediately after bootstrap.

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update cilium

helm install cilium cilium/cilium \
  --namespace kube-system \
  -f infrastructure/networking/cilium/values.yaml \
  --set k8sServiceHost=$TALOS_IP
```

Wait ~60 seconds for Cilium pods to start.

---

## Step 9 — Validate

```bash
# Node should be Ready
kubectl get nodes -o wide

# Cilium, CoreDNS, Hubble should be running — no Flannel, no kube-proxy
kubectl get pods -n kube-system

# Full Talos health check
talosctl --talosconfig clusters/lab/generated/talosconfig \
  --endpoints $TALOS_IP \
  --nodes $TALOS_IP \
  health --server=false
```

Expected node output:
```
NAME            STATUS   ROLES           AGE   VERSION
talos-XXXX-XXX  Ready    control-plane   2m    v1.36.x
```

---

## Cluster Details

| Property | Value |
|----------|-------|
| Cluster name | `nqlabs-lab` |
| API endpoint | `https://$TALOS_IP:6443` |
| Architecture | ARM64 |
| Talos version | v1.13.3 |
| Kubernetes version | v1.33.x (bundled with Talos) |
| Node role | control-plane + worker (single node) |
| Network mode | UTM Shared Network (NAT) |

---

## Troubleshooting

**VM gets no IP on the Talos console**
- Verify UTM network is set to Shared Network (not Bridged or None)
- Restart the VM

**`talosctl disks --insecure` hangs or refuses**
- Talos maintenance mode uses port 50000; confirm firewall isn't blocking it
- Verify `$TALOS_IP` is correct

**Bootstrap hangs**
- Check UTM console for kernel panics or disk errors
- Verify VM has at least 6GB RAM and 50GB disk

**Nodes stuck in `NotReady`**
- CNI is not yet installed — this is expected before Cilium is deployed
- Proceed to the CNI installation runbook

---

## If You Need to Reinstall (Reset)

If the cluster is in a bad state and you need to start over:

```bash
talosctl --talosconfig clusters/lab/generated/talosconfig \
  --endpoints $TALOS_IP \
  --nodes $TALOS_IP \
  reset --graceful=false --reboot
```

Wait ~20 seconds for the node to return to maintenance mode, then repeat from Step 5.

---

## Next Steps

1. Bootstrap ArgoCD → `docs/runbooks/argocd-bootstrap.md`
2. Verify cluster is fully operational before continuing
