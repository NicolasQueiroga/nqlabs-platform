# Guide 03 — Talos Laptop Bootstrap

## Learning objectives

By the end of this guide, a student should be able to explain:

- what Talos maintenance mode is
- why the laptop lab uses ARM64 Talos images
- why the install disk matters
- why the node is `NotReady` before a CNI exists
- what evidence proves that Talos installed successfully

For exact commands, use the operational runbook:

- [`docs/runbooks/talos-bootstrap-laptop.md`](../docs/runbooks/talos-bootstrap-laptop.md)

This guide teaches the reasoning behind that runbook.

## Context

The current lab cluster runs on:

- MacBook Pro M1 Pro
- UTM virtual machine
- Talos Linux v1.13.3
- ARM64 architecture
- UTM Shared Network, usually `192.168.64.0/24`

The future NUC cluster will be x86_64 bare metal. The laptop cluster is not meant to
match hardware exactly. It is meant to validate the platform operating model.

## Talos is not a normal Linux server

Talos has no SSH login, no package manager, and no mutable admin shell. This is a feature.

Configuration is applied through the Talos API using `talosctl`. The node moves through
states:

```text
Boot ISO → maintenance mode → apply machine config → install to disk → configured node → bootstrap Kubernetes
```

The important lesson is that the OS is managed declaratively. You do not "log in and fix"
the server. You change desired state and apply it.

## Maintenance mode

Maintenance mode is the pre-configuration state. The node has booted Talos, but it has
not yet joined any cluster.

Evidence of maintenance mode:

- Talos API responds with `--insecure`
- TLS certificate subject is `maintenance-service.talos.dev`
- no authenticated `talosconfig` is usable yet

The UTM console may show "Display output is not active." That is not failure. Talos is
headless. Use network evidence instead.

## The disk lesson: `/dev/sda` vs `/dev/vda`

Default generated Talos configs may target `/dev/sda`. In UTM, the virtual disk is
presented as a virtio block device: `/dev/vda`.

This is why the lab patch declares:

```yaml
machine:
  install:
    disk: /dev/vda
```

Exercise:

1. Find the command in the runbook that lists disks in maintenance mode.
2. Predict which disk is the install target.
3. Explain why installing to the CD-ROM device would be impossible.

## Bootstrap is a one-time event

`bootstrap` initializes etcd for the cluster. In a single-node lab cluster, this happens
on the only control plane node.

Treat bootstrap carefully:

- run it once per cluster
- do not run it as a troubleshooting reflex
- if the cluster must be recreated, reset and reinstall deliberately

## Why the node is `NotReady` before Cilium

Kubernetes needs a Container Network Interface (CNI) to provide pod networking. Without
a CNI, the API server may be running, but the node cannot fully support pods.

In this platform, Talos is configured with:

- default CNI disabled
- kube-proxy disabled
- Cilium installed separately

This lets Cilium replace both pod networking and kube-proxy service routing.

Expected sequence:

```text
Bootstrap Kubernetes → node appears NotReady → install Cilium → node becomes Ready
```

If a student expects the node to be Ready before Cilium, they have misunderstood the
networking dependency.

## Guided troubleshooting prompts

Use these questions before looking up an answer.

### The VM has no visible display

- Is the VM actually running?
- Does it have an IP on the UTM shared network?
- Can the Talos maintenance API answer a disk query?

### The node stays in maintenance mode

- Did the install disk exist?
- Was the machine config applied?
- Did the certificate subject change from `maintenance-service.talos.dev`?

### `talosctl` says it cannot determine endpoints

- Does the generated talosconfig contain endpoints?
- Which flag explicitly supplies the endpoint?
- Why is the Talos API endpoint different from the Kubernetes API endpoint?

### The node is NotReady

- Is a CNI installed?
- Are Cilium pods running?
- Is kube-proxy expected to exist in this platform?

## Checkpoint evidence

A successful lab bootstrap has evidence like:

- `kubectl cluster-info` returns the API server endpoint
- `kubectl get nodes` shows one control-plane node
- after Cilium install, the node is `Ready`
- `kubectl get pods -n kube-system` shows Cilium and CoreDNS running
- no Flannel pods are running
- no kube-proxy pods are running

## Reflection

Answer in your own words:

> Why is it better that Talos has no SSH escape hatch? What operational discipline does
> that force?

