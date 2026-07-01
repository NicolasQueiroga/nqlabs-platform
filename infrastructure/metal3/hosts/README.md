# BareMetalHost inventory for NQLabs.
#
# This directory contains BareMetalHost CRDs that register physical and
# virtual nodes with Metal3 for provisioning and lifecycle management.
#
# Each BareMetalHost references:
#   - A BMC address (Redfish for Proxmox VMs, IPMI/Redfish for physical NUCs)
#   - BMC credentials (Secret with username/password)
#   - A boot MAC address (for network boot)
#   - Hardware profile (optional)
#
# BMC for Proxmox VMs:
#   The proxmox-redfish daemon (installed on the Proxmox host) exposes a
#   Redfish API for each VM.  The BMC address format is:
#     redfish-virtualmedia+http://<proxmox-ip>:8443/redfish/v1/Systems/<vmid>
#
# BMC for physical NUCs:
#   If the NUC has IPMI/Redfish support, use the standard address format.
#   If not, set boot order to network-first and use manual power cycling.
#   BMC can be omitted — Ironic can still provision nodes without BMC,
#   but cannot power cycle them automatically.
#
# The existing management nodes (mgmt-01/02/03) are already running and
# don't need to be managed by Metal3.  They are listed here for inventory
# purposes only (with accepted: false).
#
# Future staging and production nodes will be created as Proxmox VMs or
# physical NUCs and managed by Metal3.
