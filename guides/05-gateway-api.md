# Guide 05 — Gateway API and Traffic Routing

## Learning objectives

By the end of this guide, a student should be able to explain:

- why the legacy `Ingress` resource is being replaced
- what Gateway API is and how its resources relate to each other
- why this platform uses Cilium Gateway API instead of a separate ingress controller
- how to expose a service through a `Gateway` and `HTTPRoute`
- what `GatewayClass` represents and why there is one per implementation

## The problem with Kubernetes Ingress

The `Ingress` resource has been in Kubernetes since the early days. It works, but it
has a fundamental design problem: it was too simple for complex routing needs, so every
implementation extended it using annotations.

Example Nginx-specific annotation:

```yaml
nginx.ingress.kubernetes.io/rewrite-target: /$1
nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

This means:

- routing configuration is not portable between implementations
- annotations are untyped strings — no schema validation, no IDE support
- the API gives no way to separate infrastructure concerns (who manages the gateway)
  from application concerns (who defines the routes)

Gateway API was designed to fix all of this.

## What Gateway API is

Gateway API is a set of Kubernetes CRDs maintained by the Kubernetes SIG-Network group.
It provides a structured, role-aware, portable way to define ingress and routing.

The three core resource types:

```
GatewayClass
    └── Gateway
            └── HTTPRoute / TLSRoute / GRPCRoute
```

### GatewayClass

Defines which controller implements the gateway behavior.

In this platform, Cilium creates a `GatewayClass` named `cilium` automatically when
Gateway API is enabled. This is the equivalent of an `IngressClass`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
```

A student should be able to explain: who creates this resource, and who reads it?

### Gateway

Defines a specific gateway instance — a listener on a port and protocol.

An infrastructure operator creates a `Gateway`. It references a `GatewayClass` and
defines listeners (e.g. port 80 HTTP, port 443 HTTPS).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: platform-gateway
  namespace: platform
spec:
  gatewayClassName: cilium
  listeners:
    - name: http
      protocol: HTTP
      port: 80
```

### HTTPRoute

Defines routing rules — which hostnames and paths go to which services.

Application teams create `HTTPRoute` resources. They do not need to touch the `Gateway`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
    - name: platform-gateway
      namespace: platform
  hostnames:
    - grafana.platform.nqlabs.network
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: grafana
          port: 3000
```

Notice the separation: the infrastructure team owns the `Gateway`; the application
team owns the `HTTPRoute`. This is intentional role-based design.

## Why Cilium Gateway API needs no separate controller

Traditional ingress controllers (Nginx, Traefik, HAProxy) are separate deployments
that must be installed and maintained alongside the CNI.

Cilium already runs an Envoy proxy on every node (`cilium-envoy`). When Gateway API
is enabled, Cilium's built-in controller reconciles `Gateway` and `HTTPRoute` resources
using that existing Envoy instance.

This means:

- no additional pods to deploy
- one fewer component to version, upgrade, and debug
- deep integration with Cilium's eBPF networking and observability

## The version mismatch lesson

This platform encountered a real failure when enabling Gateway API:

> Cilium 1.19.4 expected `TLSRoute` at `gateway.networking.k8s.io/v1alpha2`.
> Gateway API v1.5.1 had promoted `TLSRoute` to `v1` and disabled `v1alpha2` serving.
> The Cilium operator crashed on every start.

The fix was to re-enable `v1alpha2` serving on the `TLSRoute` CRD and pin the
install script to a compatible version (v1.2.1). The relevant install script is at:

```text
scripts/install-gateway-api-crds.sh
```

This is an important operational lesson: upstream CRD upgrades and the components
that consume them must be version-coordinated.

## Guided lab: verify Gateway API is ready

1. Confirm the `GatewayClass` named `cilium` exists.
2. Confirm its `Accepted` status is `True`.
3. Describe the `GatewayClass` and find which controller is responsible.

Hints:
- `kubectl get gatewayclass`
- `kubectl describe gatewayclass cilium`
- What would `Accepted: False` or `Unknown` indicate?

## Guided lab: expose a test service

Deploy a simple echo server and expose it through Gateway API.

### Task

Create a `Gateway` and an `HTTPRoute` that routes traffic to a test pod.

### Constraints

- Use namespace `default`
- Use hostname `echo.staging.nqlabs.network`
- The `HTTPRoute` must reference the `Gateway` by name and namespace

### Hints

1. You need a `Deployment` and a `Service` for the echo server first.
   (`ealen/echo-server` or `hashicorp/http-echo` are lightweight options.)
2. Create a `Gateway` in the same namespace referencing `gatewayClassName: cilium`.
3. Create an `HTTPRoute` with a `parentRef` pointing to your `Gateway`.
4. Check `kubectl get gateway` and `kubectl get httproute` — what status do they show?
5. What IP does the `Gateway` get? Who assigned it?

### Current platform DNS convention

The live platform uses:

- `<service>.platform.nqlabs.network` for singleton platform tools
- `<service>.staging.nqlabs.network` for staging application services
- `<service>.production.nqlabs.network` for production application services in the private platform network

The old `*.lab.nqlabs.network` pattern was intentionally removed because platform
tools such as ArgoCD and Grafana do not have separate staging/production instances.

### Validation

A successful result shows:
- `Gateway` has an assigned IP address
- `HTTPRoute` shows `Accepted: True` and `ResolvedRefs: True`
- A request to the echo service returns a response

## Troubleshooting prompts

**Gateway has no IP address**
- Is the Cilium Gateway API controller running?
- Is there a LoadBalancer IP pool configured for the cluster?
- What does `kubectl describe gateway` show in events?

**HTTPRoute shows `ResolvedRefs: False`**
- Does the backend Service exist?
- Is the port number correct?
- Is there a `ReferenceGrant` needed if route and service are in different namespaces?

**Request returns connection refused**
- Is the gateway listener on the correct port?
- Is the Service selector matching the pod labels?

## Checkpoint questions

1. What are the three core Gateway API resource types and which team typically owns each?
2. Why is `GatewayClass` necessary? What would happen if there were two Gateway
   implementations installed?
3. What is the difference between an `Ingress` annotation and an `HTTPRoute` rule?
   Which is more portable and why?
4. In this platform, where does traffic enter the cluster and how does it reach a pod?
   Draw the path: client → ??? → ??? → pod.
5. When would you use a `TLSRoute` instead of an `HTTPRoute`?
