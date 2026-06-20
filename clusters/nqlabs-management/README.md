# Cluster: nqlabs-management

Status: active — first management cluster bootstrap complete on desktop Proxmox.

Purpose: management/control services for the NQLabs Platform.

Expected services:

- ArgoCD management instance
- platform DNS / CoreDNS authority for `nqlabs.network`
- central Grafana / observability aggregation
- Alertmanager / notification routing
- Uptime Kuma status dashboard
- future Authentik, OpenBao, Harbor, Kyverno, Falco, backup orchestration

## Initial desktop VM allocation

| Field | Value |
|-------|-------|
| VMID | `131` |
| VM name | `talos-management-cp-01` |
| MAC | `BC:24:11:15:00:31` |
| Node IP | `192.168.15.31/24` |
| Role | single-node control-plane+worker for first rehearsal |
| Sizing | 8 vCPU / 32GiB RAM / 48GiB thin disk |
| Bridge | `vmbr0` |
| Cluster endpoint | `https://192.168.15.31:6443` |
| Kubernetes node name | `talos-8m9-8ow` |
| Cilium LB pool | `192.168.15.194-195` |

Scale out only after the single-node lifecycle and GitOps model are proven.

Generated files belong in `clusters/nqlabs-management/generated/` and are ignored.

## Bootstrap status

Completed on desktop Proxmox:

- VM 131 created with disk-first boot, ISO detached, autostart enabled.
- Talos v1.13.3 installed and booted from disk.
- Kubernetes v1.36.1 bootstrapped.
- Gateway API CRDs v1.2.1 installed.
- Cilium v1.19.4 installed with kube-proxy replacement, Hubble, Gateway API, and L2 announcements.
- Node is Ready.
- CoreDNS pods are Running.
- GatewayClass `cilium` is Accepted.
- Management-specific Cilium LB pool `192.168.15.194-195` is active and non-conflicting.
- In-cluster DNS and Kubernetes API reachability validated with a one-shot pod.
- ArgoCD v3.4.3 installed via Helm chart `argo-cd` 9.5.21.
- ArgoCD admin password rotated into 1Password; initial bootstrap secret deleted.
- ArgoCD server responds HTTP 200 inside the cluster.
- Cluster-aware management root app-of-apps applied and Healthy; it watches `clusters/nqlabs-management/argocd/apps`.
- `local-path-provisioner` installed and `local-path` is the default StorageClass.
- External Secrets Operator installed; `nqlabs-1password` ClusterSecretStore is Ready/Valid.
- cert-manager installed; Cloudflare ExternalSecret and ClusterIssuers are Ready.
- DNS stack installed through management-specific ArgoCD wrappers:
  - `etcd-dns` Ready with local-path PVC
  - `external-dns` Ready
  - `coredns-dns` Ready at LoadBalancer IP `192.168.15.194`
  - Wildcard external/tailnet answers resolve to Proxmox Tailscale edge `100.105.35.84`.
- Gateway stack installed through management-specific ArgoCD wrapper:
  - `platform-gateway` Programmed=True at LoadBalancer IP `192.168.15.195`
  - `nqlabs-wildcard` Certificate Ready from Let's Encrypt
  - ArgoCD HTTPRoute validated from Proxmox: HTTP 200 via SNI to `192.168.15.195`
- Legacy desktop-lab root remains intentionally unapplied to management; additional platform apps should be added through cluster-local wrappers or cluster-aware shared definitions.

1Password items:

- `talos-nqlabs-management-secrets` — Talos cluster secrets attachment
- `nqlabs-management-access` — talosconfig and kubeconfig attachments
- `argocd-nqlabs-management-admin` — ArgoCD admin credential
- `Service Account Auth Token: NQ Labs` — source token for ESO `onepassword-service-account-token`

Next: add management in-cluster split-horizon kube-dns patch, then decide how/when Proxmox HAProxy should route platform hostnames to management instead of desktop-lab.
