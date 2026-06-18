# Guide 07 — Service Factory and Demo App

## Goal

A platform is not finished when platform tools are online. It becomes useful when a
service can be added repeatably, safely, and with minimal manual work.

This guide explains the NQLabs service factory: the path from a committed service
environment file to a live HTTPS endpoint.

By the end, you should understand:

- why the platform uses a reusable Helm chart for services
- why ApplicationSet generates one ArgoCD Application per service/environment
- how staging and production are separated
- what a service team changes when releasing a new version
- how to prove the service factory works end-to-end

## Mental model

The service factory has four layers:

```text
apps/<service>/environments/*.yaml
        │
        ▼
ApplicationSet: services
        │
        ▼
ArgoCD Application: <service>-<environment>
        │
        ▼
charts/nqlabs-service → Rollout + Service + HTTPRoute
```

Each layer has a different responsibility.

| Layer | Responsibility |
|-------|----------------|
| Environment value file | Declares what one service environment wants |
| ApplicationSet | Discovers environment files and creates ArgoCD Applications |
| ArgoCD Application | Reconciles one service/environment into one namespace |
| Helm chart | Renders Kubernetes resources consistently |

The important idea: **new service environments are data, not hand-written ArgoCD
Applications**. The service owner should add or update a values file. The platform
turns that file into a running service.

## Current namespaces, clusters, and projects

The Mac lab is a single-cluster approximation of the future multi-cluster model.
Because staging and production must never share an environment boundary, the Mac lab
uses one namespace per service/environment:

```text
<service>-staging
<service>-production
```

Example:

```text
demo-staging
demo-production
payment-staging
payment-production
```

Generated service Applications use ArgoCD `CreateNamespace=true` and
`managedNamespaceMetadata` so ArgoCD creates the target namespace with the required
service, environment, and Pod Security labels.

The future NUC target is stronger: separate environment clusters with the same
service namespace name in each cluster:

```text
nqlabs-staging/payment
nqlabs-production/payment
```

The full service namespace decision, including cross-namespace connectivity and
Gateway attachment rules, is documented in
[`docs/decisions/service-namespace-model.md`](../docs/decisions/service-namespace-model.md).


Generated service Applications use separate ArgoCD AppProjects:

| Environment | AppProject |
|-------------|------------|
| staging | `services-staging` |
| production | `services-production` |

Those service projects intentionally do **not** allow cluster-scoped resources.
Service apps should not create CRDs, ClusterRoles, ClusterIssuers, GatewayClasses,
or Namespaces. Platform bootstrap owns those concerns.

## File contract

A service environment is declared at:

```text
apps/<service>/environments/<environment>.yaml
```

Example:

```yaml
app:
  name: demo

environment:
  name: staging
  namespace: demo-staging

argocd:
  project: services-staging
  valueFile: apps/demo/environments/staging.yaml

replicaCount: 1

image:
  repository: traefik/whoami
  tag: v1.11.0
  pullPolicy: IfNotPresent

imagePullSecrets: []

container:
  port: 80

rollout:
  enabled: true

service:
  port: 80

route:
  enabled: true
  host: demo.staging.nqlabs.network
```

Important fields:

| Field | Meaning |
|-------|---------|
| `app.name` | Stable service name; becomes Application, Service, Rollout, and HTTPRoute name |
| `environment.name` | Human/environment label: `staging` or `production` |
| `environment.namespace` | Kubernetes namespace to deploy into |
| `argocd.project` | Guardrail: `services-staging` or `services-production` |
| `argocd.valueFile` | Path used by ApplicationSet as Helm values |
| `image.repository` / `image.tag` | What gets deployed |
| `imagePullSecrets` | Optional Kubernetes pull secrets for private registries |
| `rollout.enabled` | Whether to render Argo Rollouts `Rollout` instead of a Deployment |
| `route.host` | Public/private DNS name routed through the platform Gateway |

## What the chart renders

`charts/nqlabs-service` currently renders:

- `ServiceAccount`
- `Service`
- `HTTPRoute` when `route.enabled=true`
- `Rollout` when `rollout.enabled=true`
- `Deployment` when `rollout.enabled=false`

The demo service uses Argo Rollouts:

```bash
kubectl get rollout -n staging demo
kubectl get rollout -n production demo
```

Expected:

```text
DESIRED   CURRENT   UP-TO-DATE   AVAILABLE
1         1         1            1
```

## DNS and routing flow

For `demo.staging.nqlabs.network`:

```text
browser/curl
  → Tailscale split DNS / CoreDNS
  → 192.168.64.193 platform Gateway
  → HTTPRoute in demo-staging namespace
  → Service demo
  → Rollout-managed pod
```

The HTTPRoute has this annotation:

```yaml
external-dns.alpha.kubernetes.io/hostname: demo.staging.nqlabs.network
```

`external-dns` sees the HTTPRoute and writes the A record into the private DNS stack.

## Validate the service factory

Check generated Applications:

```bash
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,PROJECT:.spec.project,SYNC:.status.sync.status,HEALTH:.status.health.status
```

Expected demo apps:

```text
demo-staging      services-staging      Synced   Healthy
demo-production   services-production   Synced   Healthy
```

Check generated workloads:

```bash
kubectl get pods,rollout,svc,httproute -n demo-staging
kubectl get pods,rollout,svc,httproute -n demo-production
```

Check DNS:

```bash
dig +short demo.staging.nqlabs.network
dig +short demo.production.nqlabs.network
```

Expected:

```text
192.168.64.193
```

Check HTTPS routing:

```bash
curl -k https://demo.staging.nqlabs.network
curl https://demo.production.nqlabs.network
```

Expected: a response from the `traefik/whoami` pod showing the request host and
forwarded headers.

## Releasing a new version

Today, a release is represented by changing the image tag in the environment file:

```yaml
image:
  repository: example/api
  tag: v1.2.3
```

Then:

1. Commit the value-file change.
2. Push to `main`.
3. ApplicationSet keeps the Application pointed at the same value file.
4. ArgoCD detects the new revision and syncs.
5. Argo Rollouts updates the workload.

Release automation now does the same thing through a pull request:

```text
GitHub Actions workflow_dispatch
  → build multi-arch image from services/<service>
  → push to GHCR
  → open PR changing image.repository/image.tag
  → merge PR
  → ArgoCD sync
```

The workflow is:

```text
.github/workflows/release-service.yaml
```

Inputs:

| Input | Meaning |
|-------|---------|
| `service` | Service name under `services/<service>` and `apps/<service>` |
| `environment` | Target env file: `staging` or `production` |
| `image_tag` | Optional tag; defaults to `sha-<git short sha>` |
| `update_environment` | Whether to open the environment-update PR |

The workflow publishes images to GHCR using this repository pattern:

```text
ghcr.io/<owner>/nqlabs-<service>:<tag>
```

It builds both `linux/amd64` and `linux/arm64`, so the same release path works for
the current ARM64 laptop lab and the future x86_64 NUC cluster.

The service chart supports Kubernetes `imagePullSecrets` for private registries such
as private GHCR packages or future Harbor projects:

```yaml
imagePullSecrets:
  - name: ghcr-pull-secret
```

The referenced Secret must exist in the target namespace before ArgoCD deploys the
service. Otherwise, the cluster will hit image pull failures when the environment
file moves to a private image.

The helper script used by the workflow is:

```text
scripts/update-service-image.py
```

It only updates this block in the selected environment file:

```yaml
image:
  repository: ghcr.io/<owner>/nqlabs-<service>
  tag: sha-<commit>
```

## Readiness gaps still tracked

The service factory is operational, but operational does not mean complete. The
external infrastructure review captured the maturity target well:

```text
Current: NQLabs can create and deploy a service automatically.
Target:  NQLabs can create an operational, observable, secure service automatically.
```

Current chart contract:

- `ServiceAccount`
- `Deployment` or Argo Rollouts `Rollout`
- `Service`
- Gateway API `HTTPRoute`
- `ResourceQuota`
- `LimitRange`
- `Role` / `RoleBinding`
- `CiliumNetworkPolicy`

Next service-contract hardening backlog:

- add `values.schema.json` for values validation
- add liveness/readiness/startup probes
- add secure default pod/container security contexts
- add `ServiceMonitor` for metrics scraping
- add `ExternalSecret` for service-owned secrets
- add `PodDisruptionBudget`
- add `HorizontalPodAutoscaler` support after installing `metrics-server` or another metrics API
- evolve `route` into explicit internal/public route schema, with public `.io` disabled until the public-edge phase
- add chart rendering/policy validation in CI
- add an external application repository release example that opens PRs into `nqlabs-platform`

Remaining readiness items are tracked deliberately:

- add per-service RBAC, ResourceQuota, LimitRange, and isolation templates
- harden GitHub Actions and repository rules/branch protection

These are not optional just because there is only one demo service today. The platform
should be ready before more services depend on it.

## Terraform onboarding contract

Terraform is the higher-level onboarding interface for service/product definitions.
It does not deploy directly to Kubernetes.

```text
terraform/services/<service>
  → terraform/modules/nqlabs-service
  → apps/<service>/environments/*.yaml
  → pull request
  → ApplicationSet
  → ArgoCD
```

Current module:

```text
terraform/modules/nqlabs-service
```

Current demo definition:

```text
terraform/services/demo
```

The module writes the same environment-file contract described earlier in this guide.
This keeps service onboarding declarative while preserving Git as the deployment gate.

Important boundary: Terraform/OpenTofu scaffolds service environment files. It must
not become the runtime image-release source of truth. Image releases should continue
to flow through GitHub Actions opening PRs that update the GitOps environment files.

## Service isolation contract

The service chart supports namespaced guardrail resources:

- `ResourceQuota`
- `LimitRange`
- `Role`
- `RoleBinding`
- `CiliumNetworkPolicy`

These are disabled by default so guardrails are enabled deliberately per service
environment after the allowed traffic/resource model is understood.

Example:

```yaml
resourceQuota:
  enabled: true
  hard:
    requests.cpu: "500m"
    requests.memory: 512Mi
    limits.memory: 1Gi
    pods: "4"

limitRange:
  enabled: true
  limits:
    - type: Container
      default:
        memory: 128Mi
      defaultRequest:
        cpu: 10m
        memory: 32Mi

rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["configmaps"]
      verbs: ["get", "list"]

ciliumNetworkPolicy:
  enabled: true
  enableDefaultDeny:
    ingress: true
    egress: false
```

Important caveat: `ResourceQuota` and `LimitRange` are namespace-scoped. They are
only truly per-service when the service has a dedicated namespace such as
`demo-staging` or `api-production`. The old shared `staging` / `production`
namespaces were only an early proof shape and are not the readiness target.

The service AppProjects already allow `*-staging` and `*-production` destinations.

The final multi-cluster target is stronger:

```text
nqlabs-staging/payment
nqlabs-production/payment
```

In that model, staging and production can use the same namespace name because they
live in different clusters.

## Checkpoint questions

1. Why does ApplicationSet generate Applications instead of committing one
   Application per environment by hand?
2. Why do service Applications use `services-staging` / `services-production`
   instead of the `platform` project?
3. Which layer creates DNS records for service routes?
4. What file should change when promoting a service image?
5. What evidence proves the service factory works end-to-end?
