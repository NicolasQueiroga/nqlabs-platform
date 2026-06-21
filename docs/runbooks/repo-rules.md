# Runbook — Repository rules & protection (review 5.10)

## Platform repo (`nqlabs-platform`)

### Enforced now — history protection (ruleset `main-history-protection`)

`main` blocks **force-push** (`non_fast_forward`) and **branch deletion**. Normal
fast-forward pushes are still allowed.

```bash
gh api repos/NicolasQueiroga/nqlabs-platform/rulesets        # list
```

### Deliberate trade-off: direct-to-main is allowed

We intentionally do **not** require pull requests or required status checks at the
push level on platform `main`, because:

- the operator pushes platform changes directly to `main`, and
- the **staging delivery bot commits the staging image update directly to `main`**
  (`apps/<app>/environments/staging.yaml`). Requiring PRs/checks at push level would
  break that automation.

The `validate` CI still runs on every push and PR (lint, helm-template all
descriptors against the schema, kubeconform, YAML parse, actionlint) and is visible
as a status — it just doesn't hard-block trusted direct pushes.

### Production approval is enforced by design, not branch protection

Production never deploys from a direct staging-style commit. It changes only via the
**production proposal PR** that a human reviews and merges (release tag → promote the
exact staged artifact → platform PR → merge). A routine image bump cannot reach
production, and **public exposure changes always require a reviewed PR**.

### Stricter config (optional, if moving off direct-to-main)

If you later prefer PR-gated platform changes, add to the ruleset:

- `pull_request` (require a PR) + `required_status_checks` → `validate`
- a **bypass actor** for the staging delivery bot (the `NQLABS_PLATFORM_REPO_TOKEN`
  app/user) so staging auto-delivery still works
- a path-scoped required review for `apps/*/environments/production.yaml`,
  `charts/**`, and `clusters/**`

## Application repos (e.g. `nqlabs-demo`)

Recommended rules:

- require a PR to `main` with the **build validation** check passing
- Release Please drives versioned releases/tags
- workflows use scoped fine-grained PATs:
  - `NQLABS_PLATFORM_REPO_TOKEN` (Contents RW, Pull requests RW, Metadata R on `nqlabs-platform`)
  - `NQLABS_<APP>_RELEASE_TOKEN` (Contents RW, Pull requests RW, Metadata R on the app repo)
- GHCR package write granted to the repo

See [onboarding-a-new-application.md](onboarding-a-new-application.md).
