# Preview descriptors (ephemeral)

This directory holds throwaway per-PR preview descriptors written by the app
repo's `/preview` workflow (`apps/demo/previews/pr-<n>.yaml`). The `previews`
ApplicationSet generates one ArgoCD Application per file, deployed to the staging
cluster under `demo-pr-<n>.staging.nqlabs.network`.

Lifecycle: created on `/preview deploy`, refreshed on new commits / `/preview renew`,
and removed on `/preview destroy`, PR close, or 1h TTL expiry. Do not edit by hand.
