# Roadmap — to "ultimate infra"

The service factory is complete (see [architecture/service-factory.md](architecture/service-factory.md)
and the review). What remains is platform **hardening + expansion** toward a
bank-grade, fully-featured private cloud. Tracked here.

## Delivery polish

- [x] **Exact-weight canary** — Argo Rollouts Gateway API trafficRouting plugin +
  canary/stable Services + weighted HTTPRoute (current canary is replica-ratio basic).
- [x] **Metric-driven rollouts** — AnalysisTemplates for automated promote/rollback
  (not only manual pauses).
- [x] **Public `*.io` edge** — Cloudflare Tunnel LIVE on production (cloudflared registered); add public hostnames in the CF dashboard per app — Cloudflare Tunnel / VPS reverse proxy (exposure model is
  defined; the public edge is not built).
- [x] **Preview workload selectivity** — `--workers/--scheduler` flags; default api/web
  only for multi-workload apps.

## Security / supply chain

- [x] **Kyverno** policy engine on **management** — 4 baseline ClusterPolicies in Audit
  (disallow-latest-tag, require-resource-requests, restrict-image-registries,
  require-run-as-nonroot) + verify-image-signatures. PolicyReports generating.
  - [x] replicate Kyverno to staging/production (auditing service pods there)
  - [ ] flip clean rules Audit → Enforce once the fleet passes
- [x] **Supply-chain CI** — reusable Trivy scan + Cosign keyless sign + SBOM attestation
  workflow; Kyverno verify-image-signatures audits ghcr signatures. App repos call it
  from their build (wire into `nqlabs-demo` build to activate).
  - [ ] **Harbor** self-hosted registry — DEFERRED: needs distributed storage (Rook/Ceph)
    for a non-single-node install; GHCR + scan/sign/verify covers the core meanwhile.
    Requirements: [planning/harbor-openbao-requirements.md](planning/harbor-openbao-requirements.md).
- [x] **Falco** runtime security — modern_ebpf DaemonSet live on all 3 clusters (alert mode).
- [x] CiliumNetworkPolicy **default-deny** baseline — chart supports it; live on demo
  (default-deny ingress, allow in-cluster/host/ingress; verified still reachable).
- [ ] **OpenBao** — DEFERRED (large migration). Requirements + migration plan:
  [planning/harbor-openbao-requirements.md](planning/harbor-openbao-requirements.md).

## Resilience / scale

- [~] **Velero** backup/DR — Velero+MinIO GitOps built; activate by adding 1Password
  `velero-backup` (then wire the held apps). Offsite = Cloudflare R2. Runbook: backup-velero.md.
- [ ] **Rook/Ceph** distributed storage — hardware-gated (needs spare OSD disks).
  Requirements: [planning/storage-and-ha-requirements.md](planning/storage-and-ha-requirements.md).
- [ ] **HA multi-node** clusters — hardware-gated (needs 3 CP nodes/cluster; NUCs).
  Requirements: [planning/storage-and-ha-requirements.md](planning/storage-and-ha-requirements.md).

## Operability

- [ ] **Tracing** — Tempo + OpenTelemetry Collector.
- [ ] **SSO** — Authentik/Keycloak OIDC for ArgoCD/Grafana; workload identity.

## Optional

- [ ] Hard PR-gating / required-check branch rules (if moving off direct-to-main).
- [ ] Update the Terraform service module to the current descriptor model, or retire it
  in favor of the `Create application` workflow.

---
Done already (for reference): multi-cluster GitOps service factory, named destinations,
multi-workload chart, app.yaml identity, Create application, dependency model, ConfigMap,
preview lane (+1h TTL), CI validation, schema, secure defaults, route split, repo rules.
