# Metal3 Bare Metal Provisioning

## Overview

NQLabs uses [Metal3](https://metal3.io) (CNCF Incubating) for bare metal
and virtual machine provisioning. Metal3 provides Kubernetes-native
management of physical and virtual nodes via the `BareMetalHost` CRD,
backed by [Ironic](https://ironicbaremetal.org/) for the actual
provisioning work.

### Architecture

```
Management Cluster (nqlabs-management)
├── Ironic Standalone Operator (IrSO)     — manages Ironic
├── Ironic                                  — bare metal provisioning engine
├── Bare Metal Operator (BMO)              — manages BareMetalHost CRDs
├── Cluster API Core (CAPI)                — cluster lifecycle
├── CAPI Bootstrap Provider Talos (CABPT)  — generates Talos machine configs
├── CAPI Control Plane Provider Talos (CACPPT) — manages Talos control planes
├── CAPI Provider Metal3 (CAPM3)           — infrastructure provider
├── BareMetalHost CRDs                     — node inventory
└── Cluster API resources                  — staging/production clusters

Proxmox Host (192.168.15.20)
├── proxmox-redfish daemon                 — Redfish API for VMs
└── VMs (101-103 = management, 104+ = staging/production)
```

### Components

| Component | Version | Purpose |
|-----------|---------|---------|
| IrSO | v0.10.0 | Ironic Standalone Operator |
| Ironic | v34.0 | Bare metal provisioning engine |
| BMO | v0.13.1 | Bare Metal Operator |
| CAPI | v1.13.1 | Cluster API core |
| CAPM3 | v1.13.1 | Cluster API Provider Metal3 |
| CABPT | v0.6.12 | Cluster API Bootstrap Provider Talos |
| CACPPT | v0.5.13 | Cluster API Control Plane Provider Talos |
| proxmox-redfish | latest | Redfish API emulation for Proxmox VMs |

### Networking

**Current: Virtual Media (no PXE boot)**

Ironic uses the host cluster networking (192.168.15.0/24) and provisions
nodes via virtual media (Redfish). No DHCP or TFTP is needed — Ironic
mounts an ISO to the node's BMC via Redfish and boots from it.

This works for Proxmox VMs with proxmox-redfish and for physical NUCs
that support Redfish virtual media.

**Future: PXE Boot (for NUCs without Redfish)**

When physical NUCs without Redfish virtual media are added, enable PXE
boot by updating the Ironic CR:

```yaml
spec:
  networking:
    interface: "eth0"
    ipAddress: "192.168.15.50"
    ipAddressManager: keepalived
    dhcp:
      networkCIDR: "192.168.15.0/24"
      rangeStart: "192.168.15.200"
      rangeEnd: "192.168.15.250"
```

Ironic's dnsmasq will run in proxy DHCP mode, only adding PXE boot info
without competing with the existing DHCP server at 192.168.15.1.

## Installation

### 1. Install proxmox-redfish on Proxmox host

```bash
ssh root@192.168.15.20 'bash -s' < infrastructure/metal3/proxmox-redfish/install.sh
```

After installation, edit `/etc/proxmox-redfish/params.env` to set the
Proxmox API credentials, then restart the service:

```bash
systemctl restart proxmox-redfish
```

Verify:
```bash
curl -k -u admin:admin https://192.168.15.20:8443/redfish/v1/
```

### 2. Deploy Metal3 via ArgoCD

The following ArgoCD apps are defined in the root app-of-apps:

1. `metal3-irso` (sync-wave: 1) — IrSO + Ironic instance
2. `metal3-bmo` (sync-wave: 2) — Bare Metal Operator
3. `cluster-api` (sync-wave: 1) — CAPI providers (core + Talos + Metal3)
4. `metal3-hosts` (sync-wave: 3) — BareMetalHost inventory

All apps are in the `platform` ArgoCD project and deploy to the
management cluster.

### 3. Create Proxmox VMs for staging/production

Before Metal3 can provision a node, the Proxmox VM must exist with the
correct MAC address and network configuration:

```bash
# Create staging VM (VMID 104)
ssh root@192.168.15.20 << 'EOF'
qm create 104 --name staging-cp-01 --cores 4 --memory 8192 \
  --net0 virtio=BC:24:11:15:00:20,bridge=vmbr0 \
  --scsi0 local-lvm:40 --boot order=scsi0 --ostype l26 \
  --boot order=net0 --efidisk0 local-lvm:1
qm set 104 --boot order=net0
EOF
```

### 4. Provision a node

Once the BareMetalHost is `accepted: true` and the VM exists, Metal3
will automatically:
1. Register the host with Ironic
2. Inspect the hardware
3. Set the host to `available` state

When a Cluster API cluster references the host (via Metal3MachineTemplate),
CAPM3 will:
1. Assign the host to the cluster
2. Ironic provisions the node with the Talos image
3. CABPT generates the Talos machine config
4. The node boots Talos and joins the cluster

## Operations

### Check BareMetalHost status

```bash
kubectl get bmh -n metal3
kubectl describe bmh staging-cp-01 -n metal3
```

### Check Ironic status

```bash
kubectl get ironic -n metal3
kubectl get pods -n metal3 -l app=ironic
```

### Move a node between clusters

1. Remove the node from the current cluster's MachineDeployment
2. Wait for the node to be deprovisioned (BMO will clean the disk)
3. Add the node to the new cluster's MachineDeployment
4. CAPM3 will assign the newly available BareMetalHost

### Reprovision a node

```bash
# Set the host to deprovisioned
kubectl patch bmh staging-cp-01 -n metal3 --type=merge -p '{"spec":{"online":false}}'

# Wait for it to become available
kubectl get bmh staging-cp-01 -n metal3 -w

# Set it back online
kubectl patch bmh staging-cp-01 -n metal3 --type=merge -p '{"spec":{"online":true}}'
```

## References

- [Metal3 User Guide](https://book.metal3.io)
- [Ironic Standalone Operator](https://book.metal3.io/irso/introduction)
- [Bare Metal Operator](https://book.metal3.io/bmo/install_baremetal_operator)
- [Cluster API Provider Metal3](https://book.metal3.io/capm3/introduction)
- [CABPT (Talos bootstrap)](https://github.com/siderolabs/cluster-api-bootstrap-provider-talos)
- [CACPPT (Talos control plane)](https://github.com/siderolabs/cluster-api-control-plane-provider-talos)
- [proxmox-redfish](https://github.com/v1k0d3n/proxmox-redfish)
