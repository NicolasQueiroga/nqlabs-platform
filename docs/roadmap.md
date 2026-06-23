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

- [x] **Kyverno** policy engine on all clusters — baseline policies in Enforce,
  autogen enabled for controllers, service-namespace label/limit policies,
  generate defaults for service namespaces, mutate managed labels, metrics scraped.
  Image signatures remain Audit until current app images are proven signed.
- [x] **Supply-chain CI** — reusable Trivy scan + Cosign keyless sign + SBOM attestation
  workflow; Kyverno verify-image-signatures audits ghcr signatures. App repos call it
  from their build (wire into `nqlabs-demo` build to activate).
  - [ ] **Harbor** self-hosted registry — DEFERRED: needs distributed storage (Rook/Ceph)
    for a non-single-node install; GHCR + scan/sign/verify covers the core meanwhile.
    Requirements: [planning/harbor-openbao-requirements.md](planning/harbor-openbao-requirements.md).
- [x] **Falco** runtime security — modern_ebpf DaemonSet live on all 3 clusters,
  custom NQLabs rules, metrics, validation fixture, and management Falcosidekick
  forwarding to Alertmanager.
- [x] CiliumNetworkPolicy **default-deny** baseline — chart supports it; live on demo
  (default-deny ingress, allow in-cluster/host/ingress; verified still reachable).
- [ ] **OpenBao** — DEFERRED (large migration). Requirements + migration plan:
  [planning/harbor-openbao-requirements.md](planning/harbor-openbao-requirements.md).

## Resilience / scale

- [x] **Velero** backup/DR — LIVE on management/staging/production with node-agent
  file backup, scheduled local/offsite backups, metrics, and restore-test runbook.
- [ ] **Rook/Ceph** distributed storage — hardware-gated (needs spare OSD disks).
  Requirements: [planning/storage-and-ha-requirements.md](planning/storage-and-ha-requirements.md).
- [ ] **HA multi-node** clusters — hardware-gated (needs 3 CP nodes/cluster; NUCs).
  Requirements: [planning/storage-and-ha-requirements.md](planning/storage-and-ha-requirements.md).

## Operability

- [ ] **Tracing** — Tempo + OpenTelemetry Collector.
- [x] **SSO** — Authentik IdP: OIDC for ArgoCD/Grafana + forward-auth outpost for non-OIDC UIs (see `docs/decisions/identity-provider.md`). Workload identity (SPIFFE/SPIRE) still pending.

## Optional

- [ ] Hard PR-gating / required-check branch rules (if moving off direct-to-main).
- [ ] Update the Terraform service module to the current descriptor model, or retire it
  in favor of the `Create application` workflow.

---
Done already (for reference): multi-cluster GitOps service factory, named destinations,
multi-workload chart, app.yaml identity, Create application, dependency model, ConfigMap,
preview lane (+1h TTL), CI validation, schema, secure defaults, route split, repo rules.
