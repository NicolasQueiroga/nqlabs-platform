# Runbook: Cluster Lifecycle

This runbook defines the operational shape for creating clusters and reassigning
machines. It is intentionally high level for now; exact Talos commands will be added
when moving to the desktop and NUC phases.

## Create a new cluster from new machines

Use this when adding a new hardware set, for example a future `nqlabs-lab` cluster.

High-level procedure:

1. Assign hostnames and IPs / DHCP reservations.
2. Update the IP address plan and hardware inventory.
3. Generate Talos secrets and machine configs for the new cluster.
4. Apply Talos configs to the new machines.
5. Bootstrap etcd/control plane.
6. Join remaining nodes.
7. Install Cilium and required Gateway API CRDs.
8. Bootstrap or register ArgoCD management for the cluster.
9. Register the cluster with `nqlabs-management` ArgoCD when using multi-cluster GitOps.
10. Validate DNS, Gateway, TLS, storage, monitoring, and service deployment.

## Move a machine from one cluster to another

Use this when reallocating capacity, for example moving a NUC from staging to
production.

High-level procedure:

1. Confirm the old cluster has enough capacity to lose the node.
2. Cordon and drain the node from the old cluster.
3. Remove the node from the old cluster inventory.
4. Wipe/reset the machine before joining it elsewhere.
5. Apply the target cluster Talos machine config.
6. Join the node to the target cluster.
7. Validate node health, Cilium health, storage impact, and workload scheduling.
8. Update hardware inventory, IP plan, and cluster documentation.

Never casually point an existing node at another cluster without draining and
re-provisioning it. Cluster membership is a controlled lifecycle operation.
