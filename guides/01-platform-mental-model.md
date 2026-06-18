# Guide 01 — Platform Mental Model

## Learning objectives

By the end of this guide, a student should be able to explain:

- why Kubernetes is treated as the infrastructure abstraction layer
- how Talos, Kubernetes, Cilium, ArgoCD, and the surrounding services fit together
- why the platform is separated from workloads
- what "production-grade at small scale" means

## The core idea

NQLabs Platform is not "a Kubernetes cluster with apps on it."

It is a private cloud operating environment.

That distinction matters. A Kubernetes cluster is one technical component. A platform
also includes the rules, automation, access model, recovery strategy, observability, and
operational discipline required to run workloads reliably.

The guiding principle is:

> Kubernetes is the infrastructure abstraction layer.

This means applications should not care which NUC they run on, which disk is underneath,
or which exact network path traffic takes. They consume platform interfaces: Deployments,
Services, Ingresses, PersistentVolumeClaims, Secrets, identities, policies, and metrics.

## Layer map

Think of the platform as layers, each solving a specific class of problem.

```text
Applications / Workloads
        ↓
Platform services: ingress, storage classes, certificates, secrets, observability
        ↓
GitOps delivery: ArgoCD reconciles desired state from git
        ↓
Kubernetes: scheduling, services, APIs, controllers
        ↓
Cilium: pod networking, service routing, policy, observability
        ↓
Talos Linux: minimal immutable OS for Kubernetes nodes
        ↓
Hardware / VMs: laptop now, Intel NUCs later
```

No layer should leak unnecessary detail upward. For example, a workload should request
storage from a StorageClass. It should not know which physical disk or node backs that
volume.

## Platform vs workload

The platform provides capabilities. Workloads consume capabilities.

Examples of platform capabilities:

- DNS and service discovery
- TLS certificates
- ingress routing
- persistent storage
- secrets injection
- logging and metrics
- backup and restore workflows
- identity and policy controls

Examples of workloads:

- an API server
- a database used by an application
- a dashboard or internal tool
- an experiment or research workload

This distinction prevents the platform from becoming a random collection of apps. The
platform should remain stable, boring, observable, and reusable.

## Small scale does not mean casual engineering

The first cluster runs on one UTM VM. That is not production hardware. But the learning
path should still use production habits:

- declare desired state in git
- avoid manual drift
- never commit secrets
- validate health after each layer
- document decisions
- rehearse recovery
- design for failure even before all redundancy exists

The laptop cluster is a training simulator. The operating model must be the same model
that will later run on the NUC cluster.

## Exercise: classify each component

For each component below, classify it as infrastructure, platform service, delivery
system, workload, or access layer. Do not look for a perfect answer; justify your answer.

| Component | Your classification | Why? |
|-----------|---------------------|------|
| Talos Linux | | |
| Kubernetes API server | | |
| Cilium | | |
| Cilium Gateway API | | |
| ArgoCD | | |
| Grafana | | |
| External Secrets Operator | | |
| OpenBao | | |
| Kyverno | | |
| Falco | | |
| Harbor | | |
| Rook/Ceph | | |
| Velero | | |
| OpenTelemetry Collector | | |
| A future PostgreSQL database for an application | | |
| Tailscale | | |

## Checkpoint questions

1. Why is Talos a better fit here than a general-purpose Linux distribution?
2. Why should applications not be considered part of the platform itself?
3. What does Kubernetes abstract away? What does it not abstract away?
4. Which parts of the current laptop setup are temporary, and which are architectural?

## Reflection

Write a short paragraph answering:

> If a new engineer joined NQLabs, what mental model would you give them so they do not
> mistake this for "just a home lab"?

