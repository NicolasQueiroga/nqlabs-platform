# NQLabs Platform Specification

> **Status:** NQLabs is now a live three-cluster service factory (management/staging/production). Current architecture: [./docs/architecture/service-factory.md](./docs/architecture/service-factory.md). Sections below describing single-cluster/laptop/desktop-lab stages are historical.


## Executive Summary

NQLabs Platform is a Kubernetes-native private cloud platform designed to provide secure, observable, declarative, and scalable infrastructure across heterogeneous environments while remaining fully self-hosted and under operator control.

The platform is intended to serve as a long-term infrastructure foundation capable of supporting personal, research, startup, and production workloads without coupling the platform architecture to specific hardware, applications, or deployment targets.

The platform is designed according to modern cloud-native principles and emphasizes automation, resilience, extensibility, and operational excellence.

---

# Vision

The purpose of the platform is to create a self-owned cloud operating environment that provides capabilities traditionally associated with public cloud providers while maintaining complete control over infrastructure, data, networking, identity, and operations.

The platform must:

* Remain fully self-hosted.
* Support heterogeneous infrastructure.
* Scale incrementally through the addition of resources.
* Remain declarative and automation-driven.
* Support both single-cluster and multi-cluster architectures.
* Provide a consistent operational model regardless of infrastructure size.

The platform is designed around the principle:

> Kubernetes is the infrastructure abstraction layer.

---

# Design Principles

## Kubernetes First

Kubernetes serves as the primary execution and orchestration layer.

The platform is built around Kubernetes-native concepts rather than virtual machine-centric infrastructure models.

---

## Declarative Infrastructure

Infrastructure, platform services, policies, and workloads must be represented as code.

Desired state is declared rather than manually configured.

Git serves as the authoritative source of truth.

---

## Private by Default

Infrastructure services are private unless explicitly exposed.

Administrative access is restricted through controlled networking and identity mechanisms.

Public exposure is considered an intentional exception rather than the default behavior.

---

## Automation First

Operational processes should evolve toward automation wherever practical.

Manual procedures should be replaced by repeatable, declarative, and auditable workflows.

---

## Infrastructure as a Product

The platform is treated as a product that provides services to consumers.

Applications and workloads are consumers of the platform rather than part of the platform itself.

---

## Resilience by Design

Failure is considered a normal operating condition.

The platform must be capable of recovering from:

* node failures
* service failures
* storage failures
* configuration errors
* operator mistakes

through redundancy, automation, and recovery procedures.

---

## Extensibility

The platform must support future growth without requiring architectural redesign.

Infrastructure additions should be additive rather than disruptive.

---

# Architectural Objectives

The platform shall provide:

* Compute orchestration
* Storage orchestration
* Network abstraction
* Service discovery
* Identity and access management
* Secret management
* Observability
* Workload scheduling
* Automated deployment
* Infrastructure lifecycle management
* Multi-cluster extensibility

---

# Platform Architecture

The platform consists of multiple logical layers.

## Infrastructure Layer

The infrastructure layer provides:

* Compute resources
* Storage resources
* Network resources

The platform shall support heterogeneous infrastructure.

Resource providers may vary in:

* CPU architecture
* memory capacity
* storage characteristics
* accelerator capabilities
* physical location

Infrastructure resources are treated as members of a common resource pool.

---

## Operating System Layer

Talos Linux serves as the operating system foundation.

The operating system layer must provide:

* immutability
* declarative configuration
* API-driven management
* minimal attack surface
* Kubernetes-native lifecycle management

---

## Cluster Layer

Kubernetes serves as the orchestration platform.

The cluster layer provides:

* workload scheduling
* service orchestration
* resource allocation
* cluster networking
* workload isolation

The cluster layer is responsible for transforming infrastructure resources into consumable platform resources.

---

## Networking Layer

The networking layer provides:

* service connectivity
* ingress management
* load balancing
* service discovery
* traffic policy enforcement
* network segmentation

The networking model shall support both private and public service exposure.

---

## Storage Layer

The storage layer provides:

* persistent volumes
* replication
* backup integration
* disaster recovery capabilities
* storage abstraction

Workloads interact with storage through platform-defined interfaces rather than direct infrastructure dependencies.

---

## Identity and Security Layer

The security layer provides:

* authentication
* authorization
* secret management
* certificate management
* workload isolation
* policy enforcement

Security controls must be applied consistently across the platform.

---

## Delivery Layer

The delivery layer provides:

* GitOps workflows
* deployment automation
* configuration reconciliation
* lifecycle management

All platform state should be reproducible from version-controlled definitions.

---

## Observability Layer

The observability layer provides:

* metrics
* logging
* alerting
* health monitoring
* operational visibility

Observability is considered a mandatory platform capability.

---

# Infrastructure Lifecycle Management

Infrastructure lifecycle management evolves through progressive levels of maturity.

## Level 1 — Manual Management

Infrastructure resources are provisioned and managed manually.

This level exists primarily for platform bootstrap and learning.

---

## Level 2 — Standardized Management

Provisioning procedures become repeatable and documented.

Configuration standards are established.

Infrastructure onboarding becomes predictable.

---

## Level 3 — Automated Provisioning

Provisioning becomes partially automated.

Infrastructure can be onboarded with minimal operator intervention.

---

## Level 4 — Network-Based Provisioning

Infrastructure can be provisioned through network boot and automated installation workflows.

New resources become rapidly deployable.

---

## Level 5 — Declarative Lifecycle Management

Infrastructure state becomes represented as code.

Desired infrastructure state is managed through declarative workflows.

---

## Level 6 — Cluster Lifecycle Management

Cluster lifecycle management becomes automated through dedicated control-plane technologies.

Clusters become manageable resources rather than manually operated systems.

---

# Resource Model

Infrastructure resources are classified according to capability rather than hardware identity.

Examples include:

* Control Plane Resources
* General Compute Resources
* Storage Resources
* Accelerator Resources
* Utility Resources

Classification exists to support workload placement and operational policy.

The platform shall remain independent of specific hardware models.

---

# Multi-Cluster Strategy

The platform is designed to support both:

* single-cluster deployments
* multi-cluster deployments

Multi-cluster support exists to provide:

* operational isolation
* trust boundaries
* scalability
* administrative separation

Clusters are treated as peers within a larger platform ecosystem.

---

# Naming and Service Architecture

The platform utilizes structured naming conventions to provide consistent service discovery and operational clarity.

Internal naming uses purpose-based subdomains. Platform tools are singletons and do
not carry an environment qualifier. Application services carry their deployment
environment explicitly.

```text
<service>.platform.nqlabs.network
<service>.staging.nqlabs.network
<service>.production.nqlabs.network
```

Examples:

```text
argocd.platform.nqlabs.network
grafana.platform.nqlabs.network
api.staging.nqlabs.network
api.production.nqlabs.network
```

`production` is always written in full; `prod` is intentionally avoided.

Public services use the `nqlabs.io` domain, whose DNS is managed through Cloudflare.
Public `.io` service exposure is intentionally deferred until the desktop/NUC
public-edge phase. Private/internal services use `nqlabs.network`, resolved through
Tailscale split DNS and the in-cluster CoreDNS/external-dns stack, while TLS is
publicly trusted through Cloudflare DNS-01 and Let's Encrypt.

Naming conventions exist to communicate purpose, ownership, and operational context.

---

# Operational Principles

The platform shall adhere to the following principles:

1. If infrastructure is not defined in version control, it does not exist.
2. If backups cannot be restored, they are not backups.
3. If failure scenarios have not been tested, resilience cannot be assumed.
4. Public exposure must be intentional.
5. Automation should replace repetition.
6. Simplicity should be preferred over unnecessary complexity.
7. Infrastructure should remain understandable by its operators.

---

# Future Evolution

The platform is designed to evolve without architectural disruption.

Future capabilities may include:

* Advanced identity systems
* Workload identity
* Multi-cluster federation
* Infrastructure provisioning frameworks
* Additional resource classes
* Extended automation workflows
* Enhanced operational tooling

These capabilities are considered extensions of the platform rather than architectural changes.

---

# End State

The completed platform provides a self-hosted cloud operating environment capable of delivering secure, observable, resilient, and automated infrastructure services across heterogeneous environments.

The platform remains:

* Kubernetes-native
* Declarative
* Extensible
* Vendor-independent
* Operator-controlled

The primary objective is not the hosting of specific applications, but the creation of a durable infrastructure foundation capable of supporting any future workload requirements.
