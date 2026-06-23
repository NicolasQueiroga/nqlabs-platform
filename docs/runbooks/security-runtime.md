# Runbook — Runtime security (Falco + Kyverno)

## Falco validation test

Falco runs on all clusters with `modern_ebpf`, JSON logs, metrics, and NQLabs
custom rules. Validate after Falco changes:

```bash
# Trigger the NQLabs Shell Spawned In Container rule.
kubectl apply -f infrastructure/security/falco/validation/falco-shell-validation-job.yaml

# Confirm the event reached Falco logs.
kubectl -n falco logs -l app.kubernetes.io/name=falco --tail=200 | grep 'NQLabs Shell Spawned In Container'

# Confirm metrics are exposed.
kubectl -n falco port-forward svc/falco 8765:8765
curl -s localhost:8765/metrics | grep -E 'falco_.*events|falco_kernel_events'

# Management only: confirm Alertmanager receives warning+ events through Falcosidekick.
kubectl -n falco logs deploy/falco-falcosidekick --tail=100
```

Clean up:

```bash
kubectl -n falco delete job falco-shell-validation --ignore-not-found
```

## Kyverno validation

Kyverno policies run in Enforce for baseline controls, service-namespace
guardrails, and NQLabs GHCR image signature verification.

Before promoting a new app image into a protected namespace, verify locally:

```bash
cosign verify ghcr.io/nicolasqueiroga/<app>:<tag> \
  --certificate-identity-regexp 'https://github.com/NicolasQueiroga/nqlabs-.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Useful checks:

```bash
kubectl get clusterpolicy
kubectl get policyreport -A
kubectl get clusterpolicyreport
```

Autogen is enabled, so Pod policies also validate controller templates
(Deployment/StatefulSet/DaemonSet/etc.). If a controller sync is blocked, inspect
the PolicyReport and the admission event before weakening a policy.
