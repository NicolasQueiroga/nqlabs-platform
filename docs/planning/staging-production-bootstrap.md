# Staging & Production Cluster Bootstrap Runbook

This runbook covers provisioning 6 Intel NUCs into two 3-node Talos clusters:
- **nqlabs-staging** on VLAN 10.0.20.0/24
- **nqlabs-production** on VLAN 10.0.30.0/24

## Architecture

| | Staging | Production |
|---|---------|------------|
| VLAN | 10.0.20.0/24 | 10.0.30.0/24 |
| Gateway | 10.0.20.1 | 10.0.30.1 |
| Nodes | stg-cp-01 (.10), stg-cp-02 (.11), stg-cp-03 (.12) | prd-cp-01 (.10), prd-cp-02 (.11), prd-cp-03 (.12) |
| VIP | 10.0.20.9 | 10.0.30.9 |
| LB IPAM | 10.0.20.196–197 | 10.0.30.198–199 |
| Disk | /dev/nvme0n1 | /dev/nvme0n1 |
| NIC | eno1 | eno1 |
| BMC | None | None |

## Prerequisites

1. **VLANs configured** on the switch:
   - VLAN 20 → 10.0.20.0/24 (staging)
   - VLAN 30 → 10.0.30.0/24 (production)
   - Inter-VLAN routing to 192.168.15.0/24 (management VLAN)

2. **DHCP server** on each VLAN (for initial Talos ISO boot only — static IPs are applied via machine config)

3. **Talos ISO** downloaded: `talosctl image factory-metal-amd64` or download from https://factory.talos.dev

4. **USB flash drives** (at least 2GB each)

5. **Network access** to the NUCs' DHCP IPs from the machine running `talosctl`

6. **Management cluster** is up and healthy (ArgoCD, Cilium, cert-manager, etc.)

## Step 1: Flash Talos ISO to USB

```bash
# Download Talos ISO (match the version used by management cluster)
TALOS_VERSION=v1.13.3
wget https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.iso

# Flash to USB (replace /dev/sdX with your USB device)
sudo dd if=metal-amd64.iso of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

Repeat for each NUC (or flash one USB and use it sequentially).

## Step 2: Boot NUCs from USB

1. Connect each NUC to the correct VLAN switch port
2. Insert USB, power on, enter BIOS/UEFI:
   - Set boot mode to UEFI (if not already)
   - Boot from USB
3. Talos will boot into maintenance mode and get a DHCP IP
4. Note the DHCP IP (shown on the console or check your DHCP server)

**Verify hardware assumptions:**

```bash
# From a machine on the same VLAN, check the Talos API
talosctl --nodes <dhcp-ip> health --insecure

# Get the actual NIC name and disk name
talosctl --nodes <dhcp-ip> --insecure get links
talosctl --nodes <dhcp-ip> --insecure get disks
```

If the NIC is NOT `eno1` or the disk is NOT `/dev/nvme0n1`, update:
- `clusters/nqlabs-staging/patches/controlplane.yaml` (common patch)
- `clusters/nqlabs-staging/bootstrap/talos/patch-stg-cp-XX.yaml` (per-node patches)
- `clusters/nqlabs-staging/cilium/lb-ipam.yaml` (L2 interface)
- Same for production files

## Step 3: Generate Talos Machine Configs

### Staging

```bash
cd clusters/nqlabs-staging

# Generate base configs with the cluster endpoint (VIP)
talosctl gen config nqlabs-staging https://10.0.20.9:6443 \
  --config-patch-control-plane patches/controlplane.yaml \
  -o generated/

# Generate per-node configs by applying per-node patches to the base
for i in 01 02 03; do
  talosctl gen config nqlabs-staging https://10.0.20.9:6443 \
    --config-patch-control-plane patches/controlplane.yaml \
    --config-patch-control-plane bootstrap/talos/patch-stg-cp-${i}.yaml \
    -o generated/stg-cp-${i}/
done
```

### Production

```bash
cd clusters/nqlabs-production

talosctl gen config nqlabs-production https://10.0.30.9:6443 \
  --config-patch-control-plane patches/controlplane.yaml \
  -o generated/

for i in 01 02 03; do
  talosctl gen config nqlabs-production https://10.0.30.9:6443 \
    --config-patch-control-plane patches/controlplane.yaml \
    --config-patch-control-plane bootstrap/talos/patch-prd-cp-${i}.yaml \
    -o generated/prd-cp-${i}/
done
```

## Step 4: Apply Config to Each Node

### Staging

```bash
# Apply to each node (use the DHCP IP from step 2)
# Node 1
talosctl apply-config --insecure --nodes <stg-cp-01-dhcp-ip> \
  --file clusters/nqlabs-staging/generated/stg-cp-01/controlplane.yaml

# Node 2
talosctl apply-config --insecure --nodes <stg-cp-02-dhcp-ip> \
  --file clusters/nqlabs-staging/generated/stg-cp-02/controlplane.yaml

# Node 3
talosctl apply-config --insecure --nodes <stg-cp-03-dhcp-ip> \
  --file clusters/nqlabs-staging/generated/stg-cp-03/controlplane.yaml
```

### Production

```bash
# Node 1
talosctl apply-config --insecure --nodes <prd-cp-01-dhcp-ip> \
  --file clusters/nqlabs-production/generated/prd-cp-01/controlplane.yaml

# Node 2
talosctl apply-config --insecure --nodes <prd-cp-02-dhcp-ip> \
  --file clusters/nqlabs-production/generated/prd-cp-02/controlplane.yaml

# Node 3
talosctl apply-config --insecure --nodes <prd-cp-03-dhcp-ip> \
  --file clusters/nqlabs-production/generated/prd-cp-03/controlplane.yaml
```

## Step 5: Bootstrap the Clusters

### Staging

```bash
# Bootstrap the first node (initiates etcd)
talosctl bootstrap --nodes 10.0.20.10 \
  --talosconfig clusters/nqlabs-staging/generated/talosconfig

# Wait for all nodes to be Ready
kubectl --kubeconfig clusters/nqlabs-staging/generated/kubeconfig \
  wait --for=condition=ready node --all --timeout=300s
```

### Production

```bash
talosctl bootstrap --nodes 10.0.30.10 \
  --talosconfig clusters/nqlabs-production/generated/talosconfig

kubectl --kubeconfig clusters/nqlabs-production/generated/kubeconfig \
  wait --for=condition=ready node --all --timeout=300s
```

## Step 6: Install CNI (Cilium)

### Staging

```bash
# Install Gateway API CRDs first
bash scripts/install-gateway-api-crds.sh

# Install Cilium with staging overrides
helm install cilium cilium/cilium -n kube-system \
  -f infrastructure/networking/cilium/values.yaml \
  -f clusters/nqlabs-staging/cilium/values.yaml

# Wait for Cilium to be ready
kubectl --kubeconfig clusters/nqlabs-staging/generated/kubeconfig \
  -n kube-system wait --for=condition=ready pod -l k8s-app=cilium --timeout=120s

# Uncordon nodes if needed
kubectl --kubeconfig clusters/nqlabs-staging/generated/kubeconfig \
  uncordon stg-cp-01 stg-cp-02 stg-cp-03
```

### Production

```bash
bash scripts/install-gateway-api-crds.sh

helm install cilium cilium/cilium -n kube-system \
  -f infrastructure/networking/cilium/values.yaml \
  -f clusters/nqlabs-production/cilium/values.yaml

kubectl --kubeconfig clusters/nqlabs-production/generated/kubeconfig \
  -n kube-system wait --for=condition=ready pod -l k8s-app=cilium --timeout=120s

kubectl --kubeconfig clusters/nqlabs-production/generated/kubeconfig \
  uncordon prd-cp-01 prd-cp-02 prd-cp-03
```

## Step 7: Apply CoreDNS Split-Horizon

```bash
# Staging
kubectl --kubeconfig clusters/nqlabs-staging/generated/kubeconfig \
  apply -f clusters/nqlabs-staging/bootstrap/coredns-nqlabs-stub.yaml

# Production
kubectl --kubeconfig clusters/nqlabs-production/generated/kubeconfig \
  apply -f clusters/nqlabs-production/bootstrap/coredns-nqlabs-stub.yaml
```

## Step 8: Register Clusters in ArgoCD

For each cluster, create a ServiceAccount token and register in ArgoCD.

### Staging

```bash
KUBECONFIG=clusters/nqlabs-staging/generated/kubeconfig

# Create argocd manager ServiceAccount
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF

# Get the token
STG_TOKEN=$(kubectl -n kube-system create token argocd-manager --duration=8760h)

# Get the CA cert
STG_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Register in ArgoCD (from management cluster)
kubectl --kubeconfig clusters/nqlabs-management/generated/kubeconfig \
  apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: nqlabs-staging-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: nqlabs-staging
  server: https://10.0.20.9:6443
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${STG_CA}"
      },
      "bearerToken": "${STG_TOKEN}"
    }
EOF
```

### Production

```bash
KUBECONFIG=clusters/nqlabs-production/generated/kubeconfig

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF

PRD_TOKEN=$(kubectl -n kube-system create token argocd-manager --duration=8760h)
PRD_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

kubectl --kubeconfig clusters/nqlabs-management/generated/kubeconfig \
  apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: nqlabs-production-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: nqlabs-production
  server: https://10.0.30.9:6443
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${PRD_CA}"
      },
      "bearerToken": "${PRD_TOKEN}"
    }
EOF
```

## Step 9: Enable Staging/Production in root.yaml

Once both clusters are registered in ArgoCD, remove the exclusion from
`clusters/nqlabs-management/argocd/root.yaml`:

```yaml
# Remove these from directory.exclude:
#   - staging-foundation.yaml
#   - production-foundation.yaml
```

Commit and push. ArgoCD will pick up the change and sync the staging/production
foundation apps to the new clusters.

## Step 10: Verify

```bash
# Check ArgoCD cluster registration
kubectl --kubeconfig clusters/nqlabs-management/generated/kubeconfig \
  -n argocd get clusters

# Check staging cluster
kubectl --kubeconfig clusters/nqlabs-staging/generated/kubeconfig \
  get nodes -o wide

# Check production cluster
kubectl --kubeconfig clusters/nqlabs-production/generated/kubeconfig \
  get nodes -o wide

# Check ArgoCD apps
kubectl --kubeconfig clusters/nqlabs-management/generated/kubeconfig \
  -n argocd get apps
```

## Post-Bootstrap: Update Inventory

After the NUCs are provisioned, update the placeholder MAC addresses in
`infrastructure/metal3/hosts/inventory.csv` with the real MACs and re-run
`./generate.sh`.

## Troubleshooting

### Node stays NotReady
- Check Cilium is running: `kubectl -n kube-system get pods -l k8s-app=cilium`
- Check kubelet: `talosctl --nodes <ip> service kubelet`
- May need to uncordon: `kubectl uncordon <node>`

### talosctl apply-config fails
- Ensure the NUC is in maintenance mode (booted from ISO, not installed)
- Use `--insecure` flag
- Check the DHCP IP is correct

### Cilium pods not starting
- Gateway API CRDs must be installed first
- Check `k8sServiceHost` in Cilium values matches the VIP
- Cilium startup probe takes 2-3 min (normal)

### ArgoCD can't reach cluster
- Verify inter-VLAN routing: `ping 10.0.20.9` from management cluster
- Check the cluster Secret has correct CA and token
- Verify the API server is reachable: `curl -k https://10.0.20.9:6443/healthz`

### Wrong NIC name
- Boot the NUC from USB and check: `talosctl --nodes <ip> --insecure get links`
- Update `eno1` in all patch files and lb-ipam.yaml to the actual interface name
- Re-generate configs and re-apply

### Wrong disk name
- Check: `talosctl --nodes <ip> --insecure get disks`
- Update `/dev/nvme0n1` in `patches/controlplane.yaml` to the actual disk
- Re-generate configs and re-apply
