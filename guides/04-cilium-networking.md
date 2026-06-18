# Guide 04 — Cilium and Kubernetes Networking

> This guide covers Cilium as the platform CNI. Gateway API routing is covered in
> [Guide 05 — Gateway API and Traffic Routing](./05-gateway-api.md).

## Learning objectives

By the end of this guide, a student should be able to explain:

- what problem a CNI solves
- why this platform uses Cilium instead of the default Flannel
- what kube-proxy replacement means
- what Hubble adds to network operations
- why networking must be observable, not merely functional
- why a version mismatch between Cilium and upstream CRDs can cause silent failures

## The networking problem Kubernetes creates

Kubernetes schedules pods across nodes. Pods need to communicate even when they are on
different nodes, different subnets, or recreated with different IPs.

Kubernetes defines the model. A CNI implements it.

A working CNI must support:

- pod-to-pod networking
- service routing
- node-to-pod communication
- network policy enforcement
- integration with kubelet and the API server

Without a CNI, a Kubernetes node may exist, but it is not a useful workload platform.

## Why Cilium

Cilium uses eBPF to implement high-performance networking, observability, and policy in
the Linux kernel.

For NQLabs, Cilium is attractive because it can provide:

- pod networking
- kube-proxy replacement
- network policy
- service load balancing foundations
- Hubble network observability
- future multi-cluster networking capabilities

This aligns with the platform principle: one serious networking layer, not a pile of
unrelated tools.

## kube-proxy replacement

Traditional Kubernetes clusters often run `kube-proxy` on every node. It programs packet
forwarding rules so Services can route traffic to pods.

In this platform, kube-proxy is disabled and Cilium replaces that behavior.

This means a healthy lab cluster should **not** have kube-proxy pods.

Exercise:

1. Predict what command would show whether kube-proxy is running.
2. Run the command.
3. Explain why "no kube-proxy" is success here, not failure.

## Hubble

Hubble is Cilium's network observability layer.

It helps answer questions such as:

- Which pods are talking to which services?
- Is traffic being dropped?
- Are DNS requests succeeding?
- Which network policies are affecting traffic?

In serious infrastructure, "it works" is not enough. You need to know why it works and
what changed when it stops working.

## Current lab Cilium configuration

The lab values live at:

```text
infrastructure/networking/cilium/values.yaml
```

Read that file and identify where the following are configured:

- Kubernetes IPAM mode
- kube-proxy replacement
- Talos cgroup settings
- Kubernetes API host and port
- Hubble relay and UI
- Gateway API enablement
- Operator replica count

Do not just copy the values. Explain what each setting is responsible for and what
would break if it were removed.

## The version compatibility problem

When enabling Gateway API in Cilium, a version mismatch caused the Cilium operator
to crash on every startup with:

```
no matches for kind "TLSRoute" in version "gateway.networking.k8s.io/v1alpha2"
```

The root cause: Gateway API v1.5.1 promoted `TLSRoute` from `v1alpha2` to `v1` and
set the old version to `served=false`. Cilium 1.19.4 still expected `v1alpha2`.

This is an important class of failure to understand.

Questions to reason through:

1. How would you discover which version of a CRD is served vs deprecated?
2. Why did installing v1.5.1 CRDs break a component that had been working?
3. The fix was a targeted patch: re-enable `v1alpha2` serving on the TLSRoute CRD.
   What are the risks of that approach? What is the alternative?
4. What process would prevent this in a production environment?

The lesson: upgrading upstream CRDs and upgrading the component that consumes them
must be coordinated. Version mismatches between ecosystem components are a real
operational failure mode.

## Guided lab: prove the network is healthy

Use observation, not assumptions.

1. Confirm the node is Ready.
2. Confirm Cilium pods are Running.
3. Confirm CoreDNS pods are Running.
4. Confirm there are no Flannel pods.
5. Confirm there are no kube-proxy pods.

Hints:

- all relevant pods are in `kube-system`
- labels may help, but names are enough for the first pass
- absence of a pod can be meaningful evidence

## Failure thought experiment

Imagine CoreDNS is running but application pods cannot resolve service names.

Questions to ask:

1. Is pod networking working?
2. Can pods reach the CoreDNS service IP?
3. Are DNS packets being dropped by policy?
4. Is Cilium reporting drops in Hubble?
5. Did a recent GitOps change alter network policy?

The point is not to memorize answers. The point is to build a diagnostic path.

## Checkpoint questions

1. What does a CNI do that Kubernetes itself does not do?
2. Why would replacing kube-proxy be desirable?
3. Why is Hubble part of observability rather than just networking?
4. What would change when moving from one node to six NUCs?
5. What is the relationship between Cilium and Gateway API? Are they the same thing?
6. Why does the Cilium operator have `replicas: 1` on the lab cluster?
   What should this be set to on a production cluster, and why?

