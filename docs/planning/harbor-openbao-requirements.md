# Requirements — Harbor & OpenBao (deferred milestones)

Both are deferred deliberately: each has a hard prerequisite the platform doesn't
meet yet, and OpenBao is a careful migration. This captures exactly what's needed so
we can schedule them.

---

## Harbor (self-hosted OCI registry + scanning)

**Why deferred:** Harbor is a stateful, ~8-component app (core, registry, postgres,
redis, jobservice, portal, trivy). It needs durable, ideally shared/object storage.
The clusters run **local-path** (node-bound, single-node) — not suitable for a
reliable registry.

### Prerequisites
- **Distributed storage first** (roadmap: Rook/Ceph) — Ceph RBD for Postgres/Redis
  PVCs and Ceph RGW (or external S3/MinIO) for registry blob storage.
- A cluster to host it (management is the natural home for a platform registry).
- DNS + TLS: `harbor.platform.nqlabs.network` via the gateway + cert-manager (DNS-01).
- Secrets: admin password + DB creds via ExternalSecrets (1Password/OpenBao).

### Components / install
- Chart: `harbor/harbor`. Values: external (Ceph/S3) registry storage,
  `expose.type=clusterIP` behind the gateway, internal TLS off (gateway terminates),
  Trivy scanner enabled (`trivy.enabled=true`), Postgres/Redis either in-chart
  (on Ceph PVCs) or external.

### Migration (GHCR → Harbor)
1. Create a Harbor project `nqlabs` + robot accounts (push for CI, pull for clusters).
2. App build workflows push to `harbor.platform.nqlabs.network/nqlabs/<app>` instead of
   `ghcr.io/...`. Keep the reusable supply-chain workflow (Trivy/Cosign/SBOM) — Harbor
   also scans on push.
3. Update `apps/<app>/environments/*.yaml` `image.repository`, and cluster pull
   secrets (robot account via ExternalSecret).
4. Update Kyverno `restrict-image-registries` to allow the Harbor host; tighten to
   Harbor-only once migrated.
5. Cosign: keep signing; optionally use Harbor's Cosign/Notation verification.

**Effort:** medium-large, gated on Rook/Ceph. GHCR + Trivy/Cosign/verify already
covers the supply-chain core, so Harbor is an availability/control upgrade, not a gap.

---

## OpenBao (self-hosted secrets backend + PKI)

**Why deferred:** replacing the secrets backend **and** the certificate authority is a
careful migration with broad blast radius (every secret + every TLS cert). HA OpenBao
needs Raft quorum → 3+ nodes; clusters are single control-plane VMs today.

### Prerequisites
- **Persistent storage** for Raft (Ceph RBD or local-path) and, for HA, **multi-node**
  (roadmap: NUC expansion → 3-node quorum). A single-node OpenBao is fine for a first
  cut but not HA.
- **Auto-unseal** strategy: transit auto-unseal (a small seed OpenBao) or manual unseal
  on restart. No cloud KMS available, so plan transit or accept manual.
- DNS + TLS: `openbao.platform.nqlabs.network`.

### Components / install
- Chart: `openbao/openbao`, Raft (integrated storage), `ha.enabled` once multi-node.
- Enable engines: `kv-v2` (secrets) and `pki` (CA).

### Migration A — secrets (1Password → OpenBao)
1. Stand up OpenBao, init + unseal, store the root token in 1Password (bootstrap only).
2. Recreate every secret currently in 1Password under `kv-v2` (tailscale-key, the
   NQLABS_* tokens, `cloudflared-tunnel`, future DB creds, …).
3. Add a new ESO **ClusterSecretStore** `nqlabs-openbao` (vault provider, Kubernetes
   auth). Keep `nqlabs-1password` during transition.
4. Repoint ExternalSecrets `secretStoreRef` → `nqlabs-openbao` and `remoteRef` keys to
   OpenBao paths, one component at a time; verify each Secret still materializes.
5. Decommission the 1Password ClusterSecretStore when nothing references it.

### Migration B — PKI / CA (internal CA → OpenBao PKI)
1. Enable OpenBao `pki`; create the NQLabs root + intermediate CA.
2. cert-manager: add a `vault` **ClusterIssuer** pointing at OpenBao PKI; replace the
   current internal CA ClusterIssuer.
3. Re-issue the platform certs (the `*.staging/*.production/*.platform` wildcards) from
   OpenBao; roll gateways.
4. Distribute the OpenBao root CA to clients/trust stores (same as today's internal CA).

**Effort:** large; own milestone. Sequence: storage + multi-node → OpenBao up →
secrets migration → PKI migration.

---

## Order of operations (suggested)
1. Rook/Ceph (distributed storage) — unblocks both.
2. NUC multi-node expansion — unblocks HA for OpenBao (and etcd quorum).
3. Harbor (on Ceph) — registry + scanning.
4. OpenBao (on Ceph + multi-node) — secrets then PKI.
