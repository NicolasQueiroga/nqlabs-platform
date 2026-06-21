# Roadmap — to "ultimate infra"

The service factory is complete (see [architecture/service-factory.md](architecture/service-factory.md)
and the review). What remains is platform **hardening + expansion** toward a
bank-grade, fully-featured private cloud. Tracked here.

## Delivery polish

- [x] **Exact-weight canary** — Argo Rollouts Gateway API trafficRouting plugin +
  canary/stable Services + weighted HTTPRoute (current canary is replica-ratio basic).
- [x] **Metric-driven rollouts** — AnalysisTemplates for automated promote/rollback
  (not only manual pauses).
- [~] **Public `*.io` edge** (scaffold + runbook done; needs Cloudflare tunnel token) — Cloudflare Tunnel / VPS reverse proxy (exposure model is
  defined; the public edge is not built).
- [x] **Preview workload selectivity** — `--workers/--scheduler` flags; default api/web
  only for multi-workload apps.

## Security / supply chain

- [ ] **Kyverno** policy (audit → enforce: secure defaults, approved registries, required labels).
- [ ] **Harbor** registry + **Trivy** scanning + **Cosign** signing + SBOMs.
- [ ] **Falco** runtime security (eBPF).
- [ ] CiliumNetworkPolicy **default-deny** baseline (mostly opt-in today).
- [ ] **OpenBao** — migrate the secrets backend from 1Password; OpenBao PKI replaces the internal CA.

## Resilience / scale

- [ ] **Velero** backup/DR + restore drills.
- [ ] **Rook/Ceph** distributed storage (still local-path).
- [ ] **HA multi-node** clusters — each is a single control-plane VM; NUC bare-metal expansion + etcd quorum.

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
