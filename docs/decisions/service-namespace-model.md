# Service Namespace Model

Status: selected for the Mac lab and documented as the stepping stone to the
multi-cluster target.

## Decision

The Mac lab uses one namespace per service/environment:

```text
<service>-staging
<service>-production
```

Examples:

```text
demo-staging
demo-production
payment-staging
payment-production
```

This is the single-cluster approximation of the future multi-cluster model:

```text
nqlabs-staging/<service>
nqlabs-production/<service>
```

Staging and production workloads must never share a namespace or environment boundary.

## Namespaces are not connection requirements

Services do **not** need to live in the same namespace to communicate.

Kubernetes Services have DNS names that include namespace:

```text
<service>.<namespace>.svc.cluster.local
```

Example:

```text
auth.auth-production.svc.cluster.local
payment.payment-production.svc.cluster.local
```

A workload in `payment-production` can call a Service in `auth-production` if:

1. DNS resolves the Service.
2. The target Service exists and exposes the correct port.
3. CiliumNetworkPolicy allows the traffic.
4. The application is configured to call the correct address.

Namespace separation gives each service/environment a clearer security and lifecycle
boundary. Connectivity is then intentionally allowed with policy rather than assumed
because workloads happen to share a namespace.

## What belongs in the service namespace

Resources directly owned by or consumed by the service should live in the service
namespace:

- Rollout or Deployment
- Service
- HTTPRoute for that service hostname
- ServiceAccount
- Role and RoleBinding
- ResourceQuota
- LimitRange
- CiliumNetworkPolicy
- ConfigMaps consumed by the service
- Secrets consumed by the service
- ExternalSecrets that materialize those Secrets
- imagePullSecrets used by the Pods

Important: Kubernetes Secrets and image pull Secrets are namespace-scoped. A Pod in
`payment-production` cannot mount or use a Secret from `platform` just because it
exists there. The Secret must exist in `payment-production`.

## What belongs in platform namespaces

Platform controllers and shared infrastructure remain in their own namespaces:

```text
argocd
argo-rollouts
cert-manager
dns
external-secrets
monitoring
platform
tailscale
```

Controllers can watch and reconcile resources across namespaces. They do not need to
run in the same namespace as the workloads they manage.

Examples:

- cert-manager runs in `cert-manager` but can create/update Certificates and Secrets
  elsewhere when allowed.
- External Secrets Operator runs in `external-secrets` but can reconcile
  ExternalSecrets in service namespaces.
- Argo Rollouts runs in `argo-rollouts` but manages Rollouts in service namespaces.
- Prometheus can scrape ServiceMonitors across namespaces when configured to do so.

## Gateway model

The shared Gateway remains platform-owned:

```text
namespace/platform
  Gateway/platform-gateway
```

Service routes live with their service:

```text
namespace/demo-staging
  HTTPRoute/demo
  Service/demo
  Rollout/demo
```

Traffic flow:

```text
client
  → platform/platform-gateway
  → demo-staging/HTTPRoute demo
  → demo-staging/Service demo
  → demo-staging/Pod demo
```

The Gateway is configured with:

```yaml
allowedRoutes:
  namespaces:
    from: All
```

So HTTPRoutes in service namespaces may attach to the shared platform Gateway.

A Gateway API `ReferenceGrant` is not needed for this normal service route because
the HTTPRoute and backend Service are in the same namespace. A ReferenceGrant becomes
relevant when a route in one namespace points at a backend Service in another
namespace.

## Policy model

CiliumNetworkPolicy is the preferred service policy mechanism for NQLabs because
Cilium is the platform CNI and Cilium policies support stronger controls than standard
Kubernetes NetworkPolicy.

Default stance:

- policies are generated only when explicitly enabled
- ingress/egress allow rules should be modeled before enabling deny behavior for a
  real service
- production-like services should use explicit allowlists for required internal and
  external dependencies

Example goal for a payment production service:

```text
allow ingress from platform Gateway
allow DNS
allow auth service
allow database
allow payment provider API by FQDN
allow observability endpoints
deny arbitrary egress
deny unrelated namespace traffic
```

## Future multi-cluster model

When `nqlabs-staging` and `nqlabs-production` are separate clusters, the service
namespace can use the same name in both clusters:

```text
cluster/nqlabs-staging    namespace/payment
cluster/nqlabs-production namespace/payment
```

The fully qualified environment boundary is cluster + namespace. Same namespace names
are safe only because the clusters are separate control planes.

## Validation backlog

The current demo proves that one service can be deployed into isolated staging and
production namespaces. The next useful service-isolation proof should add a second
demo service and validate intentional cross-namespace communication:

```text
frontend-production
  → backend.backend-production.svc.cluster.local
```

That test should prove:

- DNS works across service namespaces.
- CiliumNetworkPolicy allows only the intended source/target traffic.
- DNS egress is explicitly allowed where default-deny egress is enabled.
- unrelated namespace-to-namespace traffic remains denied.

This is the Mac-lab equivalent of proving service-to-service behavior before the
future staging/production cluster split.
