# Terraform module: nqlabs-service

This module generates the service environment files consumed by the NQLabs service
ApplicationSet:

```text
apps/<service>/environments/<environment>.yaml
```

It does not talk to Kubernetes directly. Git remains the deployment interface:

```text
terraform apply
  → writes/updates apps/<service>/environments/*.yaml
  → commit/PR
  → merge
  → ApplicationSet generates/updates ArgoCD Applications
  → ArgoCD syncs the service
```

Use this module to scaffold or intentionally reshape service environment files. Do
not use Terraform state as the day-to-day release control plane for image tags;
release automation should open PRs against the generated GitOps files instead.

## Example

```hcl
module "demo" {
  source    = "../../modules/nqlabs-service"
  name      = "demo"
  apps_root = "${path.module}/../../../apps"

  environments = {
    staging = {
      image_repository = "ghcr.io/nicolasqueiroga/nqlabs-demo"
      image_tag        = "sha-example"
    }

    production = {
      image_repository = "ghcr.io/nicolasqueiroga/nqlabs-demo"
      image_tag        = "sha-example"
    }
  }
}
```

Default route hostnames are:

```text
<service>.<environment>.nqlabs.network
```

Default Mac-lab namespaces are:

```text
<service>-<environment>
```

Example:

```text
demo-staging
demo-production
```

In the future multi-cluster model, staging and production can use the same service
namespace name because they target separate clusters.

For private registries, set:

```hcl
image_pull_secrets = ["ghcr-pull-secret"]
```

The referenced Kubernetes Secret must already exist in the target namespace.

## Isolation values

The module can generate service isolation values for the Helm chart:

```hcl
resource_quota = {
  enabled = true
  hard = {
    "requests.cpu"    = "500m"
    "requests.memory" = "512Mi"
    "limits.memory"   = "1Gi"
    "pods"            = "4"
  }
}

limit_range = {
  enabled = true
  default = {
    memory = "128Mi"
  }
  default_request = {
    cpu    = "10m"
    memory = "32Mi"
  }
}

rbac = {
  create = true
  rules = [
    {
      api_groups = [""]
      resources  = ["configmaps"]
      verbs      = ["get", "list"]
    }
  ]
}

cilium_network_policy = {
  enabled = true
}
```

`ResourceQuota` and `LimitRange` are namespace-scoped. Use them for true
per-service isolation only with dedicated service namespaces in the Mac lab, or with
same-named service namespaces in separate staging/production clusters later.
