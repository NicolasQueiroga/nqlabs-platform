# NQLabs Service Factory — Architecture (current)

How NQLabs turns "I want a new application" into running staging, production, and
preview environments with repeatable, plug-and-play automation. This documents the
**implemented** system; the originating north-star review lives in agent memory.

## Goal

> Create a brand-new application and get preview, staging, and production with
> repeatable automation — PR comments create previews, merges deploy staging,
> releases promote production — where the platform generates routes, workloads,
> secrets, metrics, rollout behavior, and operational defaults.

## Implementation status

| Capability | Status |
|---|---|
| Multi-cluster GitOps (management → staging/production by **name**) | ✅ implemented |
| Descriptor-driven `services` ApplicationSet (one per `apps/<app>/environments/*.yaml`) | ✅ |
| AppProjects: `services-staging` / `services-production` / `services-preview` | ✅ |
| Service chart: multi-workload, probes, HPA, PDB, ServiceMonitor, ExternalSecret | ✅ |
| Secure-by-default security contexts + internal/public/preview route split | ✅ |
| `values.schema.json` + platform CI (lint/template/kubeconform/yaml/actionlint) | ✅ |
| App-repo flow: PR build, staging-on-main, release-please, production proposal | ✅ (in app repos) |
| Preview lane: `/preview deploy|renew|destroy|status` + 1h TTL reaper | ✅ |
| Reusable, app-agnostic preview workflows (plug-and-play) | ✅ |
| ConfigMap/envFrom in the chart | ⬜ follow-up |
| Public `*.io` edge (Cloudflare Tunnel / VPS) | ⬜ future |

## Repository responsibilities

- **Application repo** — source, Dockerfile, tests, build/CI, release versioning.
- **Platform repo** — deployment contract, reusable chart, ArgoCD app generation,
  per-environment desired state, routing, policies, cluster destinations.

The platform repo holds only declarative descriptors that say *what runs where*.

## Cluster-aware delivery

The management cluster's ArgoCD generates service Applications onto the remote
environment clusters, addressed by **name** (robust to IP changes):

```text
management ArgoCD
  services ApplicationSet (apps/*/environments/*.yaml)
    → Application demo-staging      → cluster nqlabs-staging,   namespace demo
    → Application demo-production    → cluster nqlabs-production, namespace demo
```

The cluster is the environment boundary, so namespaces use the plain service name.
Cluster registration: see [../runbooks/remote-cluster-service-factory.md](../runbooks/remote-cluster-service-factory.md).

## The service chart (`charts/nqlabs-service`)

A descriptor is a values file for this chart. It renders either a single workload
(legacy top-level values) or a `workloads:` map, plus Service, internal/public/preview
HTTPRoutes, probes, HPA, PDB, ServiceMonitor, ExternalSecret, ServiceAccount — all
gated and defaulting off so simple services stay simple. Secure pod/container
contexts are on by default (opt out per workload). `values.schema.json` rejects
malformed descriptors before ArgoCD renders them.

## Exposure model

- `*.staging` / `*.production` / `*.platform` `.network` hosts are **private**
  (Tailscale split DNS) with publicly-trusted DNS-01 TLS, served via the HAProxy
  SNI edge → the per-cluster Cilium Gateway. See
  [../runbooks/cluster-and-edge-operations.md](../runbooks/cluster-and-edge-operations.md).
- Public `*.io` exposure requires an explicit, reviewed change and a real public
  edge; it is never added by a routine image bump.

## End-to-end flow

```text
PR to app repo           → build/test only  (+ optional /preview deploy)
merge to app main        → build image, update staging descriptor → ArgoCD deploys staging
release PR → vX.Y.Z tag  → promote the exact staged artifact → production platform PR → merge → ArgoCD deploys production (canary)
```

## Preview lane

Per-PR ephemeral previews with a 1h TTL, driven by PR comments and reusable
platform workflows. Full details: [../runbooks/preview-environments.md](../runbooks/preview-environments.md).

## Adding an application

Copy the app-repo caller workflows and add `apps/<app>/environments/*.yaml`
descriptors — no new AppProject, ApplicationSet, gateway, cert, DNS, or edge rule
required. Full procedure: [../runbooks/onboarding-a-new-application.md](../runbooks/onboarding-a-new-application.md).
