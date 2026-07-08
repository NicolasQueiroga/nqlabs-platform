# Cluster: nqlabs-staging

Status: planned for 3-node Intel NUC HA cluster on VLAN 10.0.20.0/24.

Purpose: staging workload cluster. Platform operators deploy staging service instances
here through management ArgoCD.

## Physical Hardware (3 Intel NUCs)

| Field | Value |
|-------|-------|
| Nodes | stg-cp-01, stg-cp-02, stg-cp-03 |
| VLAN | 10.0.20.0/24 |
| Gateway | 10.0.20.1 |
| Node IPs | 10.0.20.10, 10.0.20.11, 10.0.20.12 |
| VIP | 10.0.20.9 |
| LB IPAM | 10.0.20.196–10.0.20.197 |
| Disk | /dev/nvme0n1 (NVMe SSD — verify on first boot) |
| NIC | eno1 (Intel I219-V — verify on first boot) |
| BMC | None (manual USB boot provisioning) |
| Cluster endpoint | https://10.0.20.9:6443 |

Service namespaces use the service name directly in this cluster, e.g.
`namespace/demo`, because the cluster boundary is the environment boundary.

## Prerequisites

- VLAN 10.0.20.0/24 configured on the switch with routing to 192.168.15.0/24 (management)
- DHCP server on the staging VLAN (for initial Talos ISO boot)
- 3 Intel NUCs with NVMe SSD and Ethernet connected to the staging VLAN

## Bootstrap

See `docs/planning/staging-production-bootstrap.md` for the complete step-by-step
provisioning runbook.

Generated files belong in `clusters/nqlabs-staging/generated/` and are ignored.
