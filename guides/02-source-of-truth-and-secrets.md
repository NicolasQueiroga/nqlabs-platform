# Guide 02 — Git, Source of Truth, and Secrets

## Learning objectives

By the end of this guide, a student should be able to explain:

- why git is the platform's source of truth
- why a public infrastructure repository can still be safe
- what must never be committed
- how generated state differs from declared state
- why secret references belong in git but secret values do not

## Source of truth

The platform principle is:

> If infrastructure is not defined in version control, it does not exist.

This does not mean every generated file belongs in git. It means the desired state, the
decisions, the templates, and the repeatable procedures live in git.

Generated local state can exist on an operator machine. Examples:

- `secrets.yaml`
- `talosconfig`
- kubeconfig files
- rendered Helm output
- temporary environment files

Those files help operate the system, but they are not the public source of truth.

## Public repo discipline

This repository is public. That creates a useful constraint: every committed file must
be safe to show the world.

That does **not** mean infrastructure security depends on hiding everything. Serious
security comes from:

- strong authentication
- proper authorization
- network boundaries
- no plaintext secrets in git
- least privilege tokens
- auditable changes
- tested recovery procedures

But public visibility also means we avoid publishing unnecessary sensitive detail.

## Never commit these

Memorize this list:

- Talos `secrets.yaml`
- generated Talos machine configs containing embedded secrets
- `talosconfig`
- kubeconfigs
- API tokens
- `.env` files
- private keys
- TLS private material
- 1Password service account tokens / credentials
- ArgoCD repository credentials

The `.gitignore` exists to help, but `.gitignore` is not a substitute for judgment.

## Current secret flow

The current Phase 0 secret flow is:

```text
1Password item/field
        ↓
ExternalSecret manifest in git
        ↓
External Secrets Operator
        ↓
Kubernetes Secret in the target namespace
        ↓
Helm chart / controller / workload consumes the Secret
```

The important distinction:

- Git contains **references** such as `grafana/password` or `tailscale-key/credential`.
- 1Password contains the **secret values**.

For this platform, ESO uses the 1Password SDK provider with a service account token.
There is no 1Password Connect server in Phase 0.

## Declared vs generated state

Use this rule:

> Commit the recipe, not the secret sauce.

Examples:

| File | Commit? | Why |
|------|---------|-----|
| `clusters/lab/patches/controlplane.yaml` | Yes | It declares safe desired configuration |
| `clusters/lab/generated/controlplane.yaml` | No | It contains generated cluster material |
| `infrastructure/networking/cilium/values.yaml` | Yes | It declares Cilium configuration |
| `secrets.yaml` | No | It contains sensitive Talos secrets |
| `docs/runbooks/talos-bootstrap-laptop.md` | Yes | It documents repeatable procedure |

## Guided lab: inspect repository safety

Do this before every commit.

1. Predict which files should appear in `git status` after changing a patch file.
2. Predict which files should **not** appear after generating Talos configs.
3. Run `git status`.
4. Compare reality with your prediction.

If a secret appears in `git status`, stop. Do not stage it. Fix the ignore rules or move
the file out of the repository before continuing.

## Practical exercise

Without opening any secret file, answer:

1. Which ignore rule prevents `secrets.yaml` from being committed?
2. Which ignore rule prevents generated Talos configs from being committed?
3. Why is `clusters/lab/patches/controlplane.yaml` safe to commit even though it affects
   node configuration?
4. What would you do if a secret was accidentally committed to the public repo?

Do not skip question 4. "Delete the file" is not enough. Think through rotation,
history, and incident response.

## Checkpoint

A student is ready to continue when they can explain this sentence:

> Git stores desired platform state and educational knowledge; external secret systems
> store sensitive values; generated local files bridge the two during bootstrap.
