# Cluster: nqlabs-production

Status: planned for 3-node Intel NUC HA cluster on VLAN 10.0.30.0/24.

Purpose: production workload cluster. This is the production control-plane,
not a fake namespace inside staging or management.

## Physical Hardware (3 Intel NUCs)

| Field | Value |
|-------|-------|
| Nodes | prd-cp-01, prd-cp-02, prd-cp-03 |
| VLAN | 10.0.30.0/24 |
| Gateway | 10.0.30.1 |
| Node IPs | 10.0.30.10, 10.0.30.11, 10.0.30.12 |
| VIP | 10.0.30.9 |
| LB IPAM | 10.0.30.198–10.0.30.199 |
| Disk | /dev/nvme0n1 (NVMe SSD — verify on first boot) |
| NIC | eno1 (Intel I219-V — verify on first boot) |
| BMC | None (manual USB boot provisioning) |
| Cluster endpoint | https://10.0.30.9:6443 |

Service namespaces use the service name directly in this cluster, e.g.
`namespace/demo`, because staging/production separation is provided by separate
Kubernetes control planes.

## Prerequisites

- VLAN 10.0.30.0/24 configured on the switch with routing to 192.168.15.0/24 (management)
- DHCP server on the production VLAN (for initial Talos ISO boot)
- 3 Intel NUCs with NVMe SSD and Ethernet connected to the production VLAN

## Bootstrap

See `docs/planning/staging-production-bootstrap.md` for the complete step-by-step
provisioning runbook.

Generated files belong in `clusters/nqlabs-production/generated/` and are ignored.
