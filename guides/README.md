# NQLabs Platform Guides

These guides are the educational track for the NQLabs Platform.

The goal is that a serious computer engineering / computer science student should be
able to understand, reproduce, operate, and eventually extend this platform — not by
memorizing commands, but by learning the systems principles behind each layer.

## How these guides differ from runbooks

| Type | Location | Purpose |
|------|----------|---------|
| **Runbooks** | `docs/runbooks/` | Exact operational procedures for known tasks |
| **Guides** | `guides/` | Educational material, mental models, exercises, prompts, and checkpoints |

Runbooks are for execution. Guides are for learning.

If a guide asks you to do something, it will often provide:

- the goal
- the context
- constraints
- hints
- validation checks
- reflection questions

It will not always give the full answer immediately. That is intentional. Serious
infrastructure work requires reasoning, debugging, and reading system state.

## Learning principles

These guides follow a few educational principles:

1. **Mental models before commands** — understand the system shape before operating it.
2. **Prediction before execution** — ask what should happen before running a command.
3. **Observable checkpoints** — every lab has evidence that proves success or failure.
4. **Failure as curriculum** — errors are not interruptions; they are how operators learn.
5. **Security from the beginning** — no "temporary" bad habits around secrets, trust, or access.
6. **Production discipline at small scale** — the laptop lab is small, but the operating model is serious.

## Suggested order

### Module 1 — Foundation (Phase 0)
1. [Platform mental model](./01-platform-mental-model.md)
2. [Git, source of truth, and secrets](./02-source-of-truth-and-secrets.md)
3. [Talos laptop bootstrap](./03-talos-lab-bootstrap.md)
4. [Cilium and Kubernetes networking](./04-cilium-networking.md)
5. [Gateway API and traffic routing](./05-gateway-api.md)
6. [ArgoCD and GitOps reconciliation](./06-argocd-gitops-reconciliation.md)
7. [Service factory and demo app](./07-service-factory-and-demo-app.md)
8. cert-manager and trust chains *(coming)*
9. External Secrets and 1Password SDK *(coming)*
10. DNS, internal domains, and Tailscale access *(coming)*
11. Observability: Prometheus, Grafana, Loki, and Hubble *(coming)*

### Module 2 — NUC Cluster (Phase 1)
12. Bare-metal Talos and node lifecycle *(coming)*
13. Network design: VLANs, managed switches, and IP planning *(coming)*
14. Rook/Ceph: distributed storage, replication, and failure *(coming)*
15. Backup, restore, RTO, and RPO with Velero *(coming)*
16. PXE boot and automated node provisioning *(coming)*

### Module 3 — Operations and Security (Phase 2)
17. Kyverno: policy enforcement and admission control *(coming)*
18. Falco: runtime security and anomaly detection *(coming)*
19. Harbor: container registry, proxy cache, and vulnerability scanning *(coming)*
20. OpenBao: self-hosted secrets engine and PKI *(coming)*
21. Distributed tracing with Tempo and OpenTelemetry *(coming)*
22. Supply chain security: Cosign, Trivy, and SBOMs *(coming)*
23. SSO and identity with Authentik *(see docs/decisions/identity-provider.md + docs/runbooks/sso-authentik.md)*
24. Multi-cluster design and Cilium Cluster Mesh *(coming)*
25. Cluster lifecycle management with Cluster API *(coming)*

## Student expectations

Before moving from one guide to the next, a student should be able to answer:

- What problem did this layer solve?
- What failure modes did we introduce?
- What evidence proves the layer is healthy?
- What should never be committed to git?
- What would change when moving from the laptop lab to the NUC cluster?

If those questions feel hard, slow down. The goal is not to rush to a dashboard. The
goal is to build infrastructure that can be trusted.
