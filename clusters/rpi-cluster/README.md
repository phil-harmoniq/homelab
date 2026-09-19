# Homelab: 3-Node Talos Kubernetes Cluster

A self-hosted, high-availability homelab built on a 3-node Raspberry Pi 4 cluster running
[Talos Linux](https://www.talos.dev/) and Kubernetes. It provides HA Postgres (with off-cluster
point-in-time backups), redundant DNS, automated trusted TLS, a full self-hosted single-sign-on
(SSO) identity stack that real services authenticate against, and a unified observability stack
(metrics + logs) in Grafana. **The whole cluster is managed via GitOps (Argo CD)** — this repo is
the source of truth, and the cluster continuously reconciles to it.

> **Status:** working and stress-tested (node loss, database primary failover, and LoadBalancer
> failover all validated). Fully GitOps-managed via Argo CD. Built incrementally as a learning project.

---

## Contents

- [Homelab: 3-Node Talos Kubernetes Cluster](#homelab-3-node-talos-kubernetes-cluster)
  - [Contents](#contents)
  - [Architecture at a glance](#architecture-at-a-glance)
  - [GitOps (Argo CD)](#gitops-argo-cd)
    - [Repo layout for GitOps](#repo-layout-for-gitops)
    - [How it works](#how-it-works)
    - [Secrets: Sealed Secrets](#secrets-sealed-secrets)
    - [CNPG safety design](#cnpg-safety-design)
    - [Bootstrap order (recreating from scratch)](#bootstrap-order-recreating-from-scratch)
  - [Hardware \& platform](#hardware--platform)
  - [Networking](#networking)
    - [Reserved LoadBalancer IPs](#reserved-loadbalancer-ips)
    - [Gateway listeners](#gateway-listeners)
  - [Storage](#storage)
  - [TLS / certificates](#tls--certificates)
  - [Stateful services](#stateful-services)
    - [PostgreSQL — CloudNativePG](#postgresql--cloudnativepg)
    - [DNS — Technitium (hidden-primary cluster)](#dns--technitium-hidden-primary-cluster)
  - [Identity \& SSO](#identity--sso)
    - [Service integrations](#service-integrations)
  - [Observability (metrics \& logs)](#observability-metrics--logs)
    - [Metrics](#metrics)
    - [Logging (Loki)](#logging-loki)
  - [Backups \& disaster recovery](#backups--disaster-recovery)
  - [Naming \& domain conventions](#naming--domain-conventions)
  - [Namespaces](#namespaces)
  - [Secrets \& things you must not lose](#secrets--things-you-must-not-lose)
  - [Operational gotchas (hard-won lessons)](#operational-gotchas-hard-won-lessons)
  - [Incident lessons / recovery playbook](#incident-lessons--recovery-playbook)
    - [The catastrophic one: `allowSchedulingOnControlPlanes`](#the-catastrophic-one-allowschedulingoncontrolplanes)
    - [CNPG replica timeline divergence after multi-node reboot](#cnpg-replica-timeline-divergence-after-multi-node-reboot)
    - [Talos kubelet cert: metrics-server AND Prometheus scrapes](#talos-kubelet-cert-metrics-server-and-prometheus-scrapes)
    - [Post-recovery load imbalance](#post-recovery-load-imbalance)
    - [General recovery order](#general-recovery-order)
  - [Updating components](#updating-components)
  - [Deferred / future work](#deferred--future-work)
  - [Repository layout](#repository-layout)

---

## Architecture at a glance

```mermaid
flowchart TB
    subgraph ns_lan["Home LAN 10.1.1.0/24"]
        client["Clients / family devices"]
        optiplex["optiplex 10.1.1.2<br/>Hidden DNS primary<br/>Gitea, pgAdmin, Jellyfin, NPM"]
    end

    subgraph ns_cluster["Talos Kubernetes cluster rpi-1/2/3"]
        gw["Cilium Gateway<br/>10.1.1.200<br/>star.fivelabs.tech TLS"]

        subgraph ns_auth["namespace: auth"]
            lldap["LLDAP<br/>user directory"]
            authelia["Authelia<br/>OIDC provider"]
            valkey["Valkey<br/>sessions"]
        end

        subgraph ns_default["namespace: default"]
            pg["CloudNativePG<br/>3-instance HA Postgres"]
        end

        subgraph ns_mon["namespace: monitoring"]
            graf["Grafana + Prometheus"]
        end

        dns["Technitium DNS<br/>DaemonSet, hostNetwork<br/>10.1.1.11/12/13"]
    end

    client -->|"DNS queries"| dns
    dns -->|"zone xfer + config sync"| optiplex
    client -->|"HTTPS"| gw
    gw --> lldap
    gw --> authelia
    gw --> graf
    authelia --> lldap
    authelia --> valkey
    authelia --> pg
    lldap --> pg
    optiplex -->|"OIDC"| authelia
    optiplex -->|"LDAPS 636"| lldap
```

**Request & auth flows in words:**

- Family devices get DNS from the three in-cluster Technitium secondaries (`10.1.1.11/12/13`).
- Web apps are reached at `https://<app>.fivelabs.tech`, terminated with a trusted Let's Encrypt
  cert at the Cilium Gateway (`10.1.1.200`).
- **OIDC apps** (Gitea, pgAdmin) redirect to Authelia (`auth.fivelabs.tech`), which authenticates
  the user against LLDAP, stores sessions in Valkey and state in Postgres.
- **Jellyfin** authenticates **directly against LLDAP over LDAPS** (no Authelia in the path) so
  native TV/phone clients keep working.

---

## GitOps (Argo CD)

The cluster is managed with **Argo CD** using the **app-of-apps** pattern. This repo is the single
source of truth: to change the cluster you edit a manifest, commit, and push — Argo reconciles the
cluster to match. Most apps **auto-sync with self-heal**, so manual `kubectl`/`helm` drift is
reverted automatically. This directly prevents the drift class that previously caused an outage (a
dropped Talos setting) and repeated Helm `--reuse-values` divergence.

### Repo layout for GitOps

```
clusters/rpi-cluster/
├── bootstrap/     # Argo install (values + HTTPRoute) — the manual base layer
├── root/
│   └── root-app.yaml      # app-of-apps root: watches apps/, creates all child Applications
├── apps/          # one Argo Application per component (the "index" of what's deployed)
└── manifests/     # the actual k8s YAML + Helm values, per component
    ├── networking/  storage/  dns/  cert-manager/
    ├── identity/  monitoring/  loki/  alloy/  cnpg/  sealed-secrets/
```

Talos **node** config stays in `hosts/talos/` — it's managed by `talosctl`, **not** Argo (Argo
manages in-cluster resources only).

### How it works

- **Root app** (`root/root-app.yaml`) points at `apps/`. Adding a component = commit a new
  `apps/<name>.yaml` and push; the root creates the child Application automatically.
- **Plain-manifest apps** (networking, dns, etc.) use a git `path` source.
- **Helm apps** (loki, alloy, monitoring, sealed-secrets) use a Helm chart source. Where a component
  also has plain manifests (routes, sealed secrets), a **multi-source** Application combines the Helm
  chart with a git `path` source, using `ref: values` + `$values/...` so the Helm chart reads its
  values file from git. The path source excludes the values YAMLs (they aren't k8s resources) via
  `directory.exclude`.
- **Sync policy:** everything auto-syncs (`prune: false`, `selfHeal: true`) **except CNPG**, which is
  **deliberately manual** — database spec changes should be applied on purpose after review, never
  auto-reconciled. `prune: false` everywhere means Argo never auto-deletes (safety over strict
  GitOps for a homelab).

### Secrets: Sealed Secrets

Secrets are committed to git **encrypted** using [Sealed Secrets](https://github.com/bitnami/sealed-secrets):
`kubeseal` encrypts a Secret with the controller's public key into a `SealedSecret` (safe to commit);
the in-cluster controller decrypts it. Sealed secrets in this repo: `loki-s3-creds`, `grafana-oidc`,
`grafana-admin`, `minio-backup-creds`.

- **The controller's private key is the master key** — it decrypts everything. It's backed up
  **off-cluster** (in the password manager), NOT in git. On a cluster rebuild, restore this key first
  or every committed SealedSecret becomes undecryptable.
- **Loki S3 creds** are injected as `AWS_*` env vars via `global.extraEnvFrom` (the AWS SDK reads
  them natively) — this replaced inline creds, so `loki-values.yaml` is now committable.
- **CNPG-generated secrets are NOT sealed** (`pg-app`, `pg-superuser`, the TLS certs,
  `lldap-db-app`, `authelia-db-app`) — CNPG owns and manages those. Only the manually-created
  `minio-backup-creds` needed sealing.

### CNPG safety design

The database is the highest-stakes component, so its Application has extra guards:
- **Manual sync** (not auto) — deliberate application of any change.
- **`Prune=false`** — Argo never deletes CNPG resources.
- **`Delete=false` annotation** on the `pg` Cluster — even deleting the Application won't
  cascade-delete the database.
- **`ServerSideApply=true`** + `ignoreDifferences` for CNPG-mutated fields (`.status`,
  `.spec.instances`, and defaulted role/plugin fields) so the operator's own changes don't show as
  drift.
- PVCs are CNPG-created (not in git), so Argo never manages/prunes them.

### Bootstrap order (recreating from scratch)

Argo can't manage what must exist before Argo: **Talos → Cilium (CNI) → Argo CD → Sealed Secrets
controller (+ restore its master key) → create any not-in-git secrets → apply the root app** (which
brings up everything else). See `bootstrap/` and the [recreate runbook](#deferred--future-work).

---

## Hardware & platform

| Layer | Choice | Notes |
|---|---|---|
| Nodes | 3× Raspberry Pi 4 (8GB) | `rpi-1/2/3` = `10.1.1.11/12/13` |
| Disks | Samsung 870 EVO SSD via USB3 UASP adapter | Replaced flash drives that couldn't sustain etcd fsync |
| OS | Talos Linux (immutable, API-managed) | Install disk `/dev/sda` |
| Kubernetes | v1.36.2 | Bootstrapped by Talos |
| Roles | All 3 nodes control-plane **and** worker | `allowSchedulingOnControlPlanes: true` |
| API endpoint | `https://10.1.1.10:6443` | Talos-managed VIP |

The control plane tolerates one node failure (etcd quorum of 3). Node reboots rejoin etcd
automatically (learner → full member).

---

## Networking

Everything is handled by **Cilium** — no MetalLB, no Flannel, no kube-proxy.

- **CNI + kube-proxy replacement** (via KubePrism at `localhost:7445`).
- **LoadBalancer IPAM** — pool `10.1.1.200–250`, assigned via `CiliumLoadBalancerIPPool`.
- **L2 announcement** — lease-based, on interface `end0`; proven failover with zero dropped requests.
- **Gateway API** — a single `Gateway` ("main-gateway") pinned to `10.1.1.200`.

### Reserved LoadBalancer IPs

| IP | Service |
|---|---|
| `10.1.1.200` | Cilium Gateway (all `*.fivelabs.tech` web traffic) |
| `10.1.1.201` | LLDAP LDAPS (`ldap.fivelabs.tech`, 636 → 6360) |
| `10.1.1.202` | Postgres primary (`db.fivelabs.tech`, follows failover) |

### Gateway listeners

- **HTTP (80)** — a catch-all `HTTPRoute` that 301-redirects all `*.fivelabs.tech` to HTTPS.
- **HTTPS (443, `https-fivelabs`)** — hostname `*.fivelabs.tech`, TLS terminated with the
  wildcard cert. Apps attach with an `HTTPRoute` bound to `sectionName: https-fivelabs`.

> **Adding a new web service:** create an `HTTPRoute` bound to `https-fivelabs`. It automatically
> gets the wildcard cert **and** the HTTP→HTTPS redirect — no new DNS record or cert needed.

---

## Storage

- **local-path-provisioner** is the default `StorageClass` — node-local storage on each SSD.
- Path is `/var/local-path-provisioner` (**not** `/var/mnt`, which Talos mounts read-only).
- `WaitForFirstConsumer` — a PVC stays `Pending` until a pod mounts it (this is normal).
- Node-pinned: a volume lives on one node's disk; if that node is down, the pod waits for it.
- **PVC size is effectively immutable** — local-path does **not** support volume expansion. You
  cannot grow a PVC in place; changing storage size requires recreating the workload (see
  [Updating components](#updating-components)). If you expect to resize storage, use a provisioner
  that supports expansion (e.g. Longhorn) instead.

---

## TLS / certificates

- **cert-manager** with a **Let's Encrypt** `ClusterIssuer` using a **Cloudflare DNS-01** solver.
- Issues a trusted **wildcard** cert for `fivelabs.tech` + `*.fivelabs.tech` (auto-renewing).
- The cert is issued into every namespace that needs it (e.g. `default` for the Gateway, `auth`
  for LLDAP's LDAPS) via per-namespace `Certificate` resources.

> **Split-horizon note (important):** because internal Technitium is authoritative for
> `fivelabs.tech`, cert-manager's DNS-01 self-check is forced onto public resolvers so it can see
> the ACME TXT record at Cloudflare:
>
> ```
> --dns01-recursive-nameservers-only
> --dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53
> ```
>
> Set via `helm upgrade cert-manager ... --set "extraArgs={...}"`. Without this, issuance hangs on
> "record not yet propagated" even though the record is live publicly.

Infrastructure names under `*.lan` / `*.k8s.lan` are fake TLDs and **cannot** get Let's Encrypt
certs — they would need a local CA issuer (deferred).

---

## Stateful services

### PostgreSQL — CloudNativePG

- A 3-instance HA `Cluster` ("pg"), one instance per node (anti-affinity), streaming replication.
- **Automatic failover** (~2s) — the `pg-rw` service always points at the current primary.
- In-cluster: `pg-rw.default.svc.cluster.local:5432` (`sslmode=require`).
- External: `10.1.1.202` / `db.fivelabs.tech` via a LoadBalancer that follows the primary.
- **Per-app databases** are created declaratively with the `Database` CRD; **per-app roles** with
  `managed.roles` in the Cluster spec.
- Break-glass superuser is enabled for admin/emergency use only.

### DNS — Technitium (hidden-primary cluster)

- **Primary** (source of truth) runs *outside* the cluster on `optiplex` (10.1.1.2). It is
  **hidden** — never handed to clients.
- **Secondaries** run in-cluster as a **DaemonSet** with `hostNetwork`, bound to the node static
  IPs `10.1.1.11/12/13`. These are the resolvers clients actually use (via DHCP).
- A **configurator sidecar** applies per-node settings (DNS listener bound to the node IP, HTTPS
  on 53443) via the Technitium HTTP API on boot, so the DaemonSet is reproducible.
- Zones replicate primary → secondaries; config syncs via Technitium clustering.

---

## Identity & SSO

All in namespace `auth`.

```mermaid
flowchart LR
    user["User"]
    app["App: Gitea / pgAdmin"]
    authelia["Authelia<br/>auth.fivelabs.tech"]
    lldap["LLDAP<br/>directory"]
    valkey["Valkey<br/>sessions"]
    pg["Postgres<br/>state"]
    jellyfin["Jellyfin"]

    user --> app
    app -->|"OIDC redirect"| authelia
    authelia --> lldap
    authelia --> valkey
    authelia --> pg
    jellyfin -->|"LDAPS direct"| lldap
    user --> jellyfin
```

| Component | Role |
|---|---|
| **LLDAP** | User directory (LDAP). Postgres-backed; stateless via a stable `KEY_SEED`. Web UI at `lldap.fivelabs.tech`; LDAPS on the LAN at `ldap.fivelabs.tech:636`. |
| **Authelia** | OIDC identity provider. Authenticates against LLDAP; state in Postgres, sessions in Valkey. Portal at `auth.fivelabs.tech`. |
| **Valkey** | Redis-compatible session store for Authelia (ephemeral, single replica). |

### Service integrations

| Service | Location | Method | Notes |
|---|---|---|---|
| Gitea | optiplex | **OIDC** via Authelia | Native OIDC support |
| pgAdmin | optiplex | **OIDC** via Authelia | Configured in `config_local.py` |
| Grafana | cluster | **OIDC** via Authelia | Local login form disabled; `admin` LLDAP group → Grafana Admin (via `role_attribute_path`), else Viewer |
| Nextcloud | optiplex | **OIDC** via Authelia (`user_oidc`) | `family` group required (enforced in Authelia `access_control`); `admin` group → Nextcloud admin; local form hidden, break-glass at `/login?direct=1` |
| OnlyOffice | optiplex | **none** (rides Nextcloud) | Document Server trusts Nextcloud via shared JWT; not an Authelia client |
| Jellyfin | optiplex | **LDAP direct** (LDAPS) | Authelia deliberately *not* in front — preserves native app clients |
| NPM | optiplex | none | Legacy reverse proxy, being phased out |

**Design principle:** OIDC where the app supports it; LDAP-direct for Jellyfin so streaming
clients keep working; OnlyOffice rides Nextcloud's session (never put an auth proxy in front of it).
Local break-glass accounts are always retained (e.g. Jellyfin `admin`/`tv`, Nextcloud local `admin`
via `/login?direct=1`).

---

## Observability (metrics & logs)

### Metrics

- **kube-prometheus-stack** (Helm) in namespace `monitoring`: Prometheus, Grafana, Alertmanager,
  kube-state-metrics, and node-exporter.
- **metrics-server** (Helm, `kube-system`) provides the Kubernetes Metrics API (`kubectl top`, live
  CPU/memory in Freelens/dashboards). Installed with `--kubelet-insecure-tls` on Talos (see the
  incident-lessons note on kubelet cert SANs). Kubelet serving-cert rotation is also enabled via a
  `KubeletConfig` doc + the cert-approver.
- The `monitoring` namespace must enforce PodSecurity **`privileged`** — node-exporter legitimately
  requires `hostNetwork`, `hostPID`, `hostPath`, and a `hostPort`.
- Grafana is exposed at `grafana.fivelabs.tech` via the Gateway (TLS, wildcard cert, no new DNS).
- Grafana auth is **OIDC via Authelia** (`[auth.generic_oauth]` set through the chart's
  `grafana.ini` values; client secret injected from the `grafana-oidc` Secret via `$__env{}`). The
  local login form is disabled (`[auth] disable_login_form = true`) — break-glass is reverting that
  value and re-running `helm upgrade`. `role_attribute_path` maps the `admin` LLDAP group to Grafana
  **Admin**, everyone else to **Viewer**. Server-side token/userinfo calls use the public
  `auth.fivelabs.tech` URLs (the Grafana pod reaches them fine via the Gateway).

### Logging (Loki)

Log aggregation via **Grafana Loki**, queried in the same Grafana as metrics.

| Piece | Detail |
|---|---|
| Store/query engine | **Loki** (Helm, `grafana-community/loki`), **Monolithic** mode, single replica, namespace `loki` |
| Chunk storage | **MinIO** on optiplex (bucket `loki-logs`), same S3 backend pattern as Postgres backups |
| Collection (cluster) | **Grafana Alloy** DaemonSet (namespace `alloy`, PodSecurity `privileged`) — scrapes every pod's stdout, labels with `namespace`/`pod`/`container`/`app`, ships to Loki. (Promtail is EOL; Alloy replaces it.) |
| Collection (external app) | The ASP.NET app on optiplex pushes directly via the **`Serilog.Sinks.Grafana.Loki`** sink (JSON format) — it's outside the cluster, so Alloy doesn't cover it |
| App push endpoint | `https://loki.fivelabs.tech` (HTTPRoute on the Gateway, TLS via wildcard cert) — the sink appends `/loki/api/v1/push` automatically |
| Retention | 7 days (`retention_period: 168h` + compactor `retention_enabled`) |
| Grafana datasource | Loki at `http://loki.loki.svc.cluster.local:3100` |

**Label discipline (the core Loki concept):** labels are the index — keep them **few and
low-cardinality** (`app`, `environment`, `namespace`). Everything else (versions, request IDs, the
message, enriched properties) rides as log **content**, queried with a parser (`| json` or
`| logfmt`), *not* promoted to labels. The Serilog sink is configured with
`propertiesAsLabels: []` precisely to keep enriched properties as content.

**Querying:** Go services (Loki, Authelia, cert-manager, CNPG) log **logfmt** → parse with
`| logfmt`. The ASP.NET app logs **JSON** → parse with `| json`. Filter on the real level field
(e.g. `| json | level=~"(?i)error|warn"`), not a substring `|= "error"` (which false-matches any
line mentioning the word). Cluster logs and the app share one Loki; the app is queried by
`{app="engagency"}` and also carries `namespace="engagency"` so it appears in the cluster dashboard's
namespace dropdown.

**Dashboards:** a "Cluster Logs Overview" (log volume, by-namespace, errors-by-namespace, recent
error lines, with a `namespace` template variable) and a separate app-specific dashboard for the
ASP.NET service.

> Seq was retired in favour of Loki (licensing/open-source motivation); the Seq quadlet on optiplex
> was decommissioned after a parallel bake period confirmed Loki captured everything.

---

## Backups & disaster recovery

PostgreSQL is backed up to **MinIO** (S3-compatible object storage) running as a podman quadlet
on **optiplex** (`10.1.1.2`) — deliberately *outside* the cluster, so backups survive the whole
cluster failing. Backups use CNPG's **Barman Cloud Plugin** (the in-tree `barmanObjectStore` is
removed as of CNPG 1.30).

**What's protected & how:**

| Piece | Detail |
|---|---|
| Object store | MinIO on optiplex, bucket `s3://cnpg-backups/`, endpoint `http://10.1.1.2:9000` |
| Base backups | Nightly `ScheduledBackup` at `0 0 8 * * *` (08:00 UTC = 3 AM EST / 4 AM EDT) |
| WAL archiving | Continuous (plugin `isWALArchiver: true`) — enables **point-in-time recovery** |
| Compression | gzip on both base and WAL |
| Retention | 30 days (older backups pruned automatically) |
| Credentials | MinIO service-account key in Secret `minio-backup-creds` (namespace `default`, keys `ACCESS_KEY_ID` / `ACCESS_SECRET_KEY`) — **not** the MinIO root password |

**Components:**

- `ObjectStore` (`minio-store`) — connects CNPG to MinIO (`barmancloud.cnpg.io/v1`).
- `Cluster` `plugins:` block — enables the plugin + WAL archiving on the `pg` cluster.
- `ScheduledBackup` (`pg-nightly`) — the nightly base backup.
- The **Barman Cloud Plugin** itself is installed in `cnpg-system` (depends on cert-manager, which
  is already present).

**Verifying backups land:**

```bash
kubectl -n default get backup                      # recent backups should show "completed"
# from optiplex, list the bucket contents:
mc ls -r localminio/cnpg-backups                    # base/ dirs + wals/ segments
```

**Restore (disaster recovery):** CNPG restores by bootstrapping a *new* cluster from the
`minio-store` ObjectStore via a `bootstrap.recovery` stanza (optionally to a specific point in time
via `recoveryTarget.targetTime`, using the archived WAL). The recovery cluster must be **read-only**
against the store — reference the source `serverName: pg` in an `externalClusters` entry and **omit**
the top-level `plugins:` WAL-archiver block, so the test cluster can't overwrite the real backups
(CNPG's "WAL archive check" safety net guards against this too).

> **Restore verified:** last successfully test-restored **2026-09-01** — bootstrapped a throwaway
> single-instance cluster from MinIO, confirmed all databases (`app`, `authelia`, `lldap`,
> `engagency*`) and row-level data recovered, then tore it down. Re-test periodically (a backup
> system that silently breaks is a classic failure mode).

> **MinIO console caveat:** recent MinIO community builds ship a browser-only console (no
> user/key/policy management in the UI). Create access keys and policies with the `mc` CLI
> (`mc admin user svcacct add ...`), not the web console.

> **Known limitation — backup traffic is plaintext HTTP (accepted for now).** CNPG reaches MinIO
> over `http://10.1.1.2:9000`, so the S3 credentials and backup data cross the LAN unencrypted.
> This is an accepted tradeoff on the trusted home LAN. To secure it, give MinIO a TLS cert and
> switch the `ObjectStore` to `https://` with the plugin's `endpointCA` field pointing at the
> issuing CA. This is folded into the **future local-CA project** (see below) — issue a MinIO server
> cert from the local root CA, serve HTTPS on optiplex, and have CNPG trust it via `endpointCA`.

---

## Naming & domain conventions

| Pattern | Meaning | TLS |
|---|---|---|
| `*.fivelabs.tech` | Family-facing / "complete" services. Real registered domain, used **only internally**. | Let's Encrypt (trusted) |
| `*.lan`, `*.k8s.lan` | Infrastructure. Fake TLDs. | Would need a local CA (deferred) |

DNS specifics:
- `*.fivelabs.tech` wildcard → `10.1.1.200` (the Gateway).
- Specific records **override** the wildcard — e.g. `db.fivelabs.tech` → `10.1.1.202`,
  `ldap.fivelabs.tech` → `10.1.1.201`. When migrating a service off optiplex, delete its specific
  `10.1.1.2` record so the wildcard takes over.

---

## Namespaces

| Namespace | Contents | PodSecurity |
|---|---|---|
| `default` | Cilium Gateway, CNPG Postgres cluster + LB, wildcard Certificate | (warns at restricted) |
| `auth` | LLDAP, Authelia, Valkey | baseline |
| `monitoring` | kube-prometheus-stack | **privileged** |
| `loki` | Loki (log store) | baseline |
| `alloy` | Grafana Alloy (log collector DaemonSet) | **privileged** (hostPath log access) |
| `technitium` | DNS DaemonSet | **privileged** (hostNetwork) |
| `cnpg-system` | CloudNativePG operator | — |
| `cert-manager` | cert-manager | — |
| `local-path-storage` | storage provisioner | privileged |

---

## Secrets & things you must not lose

**Kept out of git** (documented as required, created out-of-band):

- CNPG app/role secrets (`lldap-db-app`, `authelia-db-app`, `pg-app`)
- `lldap-secrets`, `authelia-secrets`, `valkey-auth`
- Cloudflare API token (`cloudflare-api-token`, namespace `cert-manager`)
- Technitium admin password
- Plaintext OIDC client secrets (live on the app side: Gitea auth source, pgAdmin `config_local.py`)
- `talosconfig`, `kubeconfig`, per-node Talos machine configs

**Permanent — losing these is unrecoverable:**

| Secret | Consequence if lost/changed |
|---|---|
| LLDAP `KEY_SEED` | Invalidates **all** stored user passwords |
| Authelia `storage-encryption-key` | Makes stored TOTP secrets & OIDC tokens unrecoverable |

Back these up somewhere durable and offline.

---

## Operational gotchas (hard-won lessons)

- **Talos `/var/mnt` is read-only** (reserved for user volumes). Use `/var/local-path-provisioner`
  for the storage provisioner path.
- **local-path PVCs can't be resized — growing storage wedges CNPG.** Bumping a CNPG cluster's
  `spec.storage.size` on local-path makes the operator try to resize existing PVCs; local-path
  refuses, the reconcile loop errors every cycle (and stops creating/managing instances), and the
  webhook then blocks shrinking the value back. Recovery = delete the `Cluster` + PVCs and recreate
  at the target size, restoring from a `pg_dumpall` backup. Take the backup *before* touching size.
- **Talos runs host DNS on `127.0.0.53:53`.** A `hostNetwork` DNS server (Technitium) must bind the
  **specific node IP**, not `0.0.0.0`, or the `:53` bind fails.
- **cert-manager split-horizon:** point the DNS-01 self-check at public resolvers (see
  [TLS](#tls--certificates)).
- **Cilium + cert-manager Gateway TLS:** create the `Certificate` (and its `kubernetes.io/tls`
  Secret) **before** the Gateway listener references it — otherwise Cilium pre-creates an `Opaque`
  placeholder secret that blocks cert-manager.
- **Technitium zone transfer + NAT:** if the primary runs on a NAT'd container network (e.g. a
  podman bridge with published ports), inbound source IPs are masqueraded to the bridge gateway, so
  **IP-based zone-transfer ACLs won't match** the real secondary IPs. Use host networking, or allow
  the transfer explicitly.
- **LLDAP entrypoint runs `chown` unconditionally.** Under a locked-down `securityContext` it needs
  either to start as root (with `CHOWN`/`SETUID`/`SETGID`/`DAC_OVERRIDE` capabilities) or a fully
  non-root image variant.
- **Authelia is strict about config** — a single bad key stops it booting (which takes down auth for
  everything behind it). Notable: set `enableServiceLinks: false` (k8s injects `AUTHELIA_*` service
  env vars it misreads); OIDC requires ≥1 client and a `jwks` key; the issuer key is injected via
  the config **template filter** (`X_AUTHELIA_CONFIG_FILTERS=template`), not an env var.
- **kube-prometheus-stack node-exporter** needs the namespace at PodSecurity `privileged`; after
  relabeling, roll the DaemonSet so it retries admission.
- **`169.254.169.254` in an S3 client's logs = "credentials not found."** It's the AWS EC2 metadata
  endpoint; the SDK falls back to it when it got no keys, then times out. Seen with Loki when its
  MinIO credentials weren't wired — it's a credentials problem, not a network one.
- **The Loki Helm chart's S3-credential injection via `extraEnv`/`-config.expand-env=true` is
  unreliable** (documented in upstream issues; it silently doesn't wire through for some pods/modes).
  Pragmatic fix: put the MinIO key/secret **inline** in the `s3` config and gitignore the values
  file (commit a `*.example.yaml` with placeholders). Also: the chart's default cache pods
  (`chunks-cache`/`results-cache`) request too much memory to schedule on a Pi — disable them; and
  default health-probe timeouts (`1s`) are too tight for ARM startup — loosen them.
- **Loki chart chart-key renames:** the chart moved to the `grafana-community` repo, `SingleBinary`
  became `Monolithic`, and the bundled MinIO is deprecated — use an external MinIO with
  `minio.enabled: false`.
- **`kubectl apply` says "unchanged"** when the file on disk wasn't actually rewritten — delete +
  recreate to force a clean roll when in doubt.
- **`kubectl logs deploy/x`** grabs only one pod; use `-l <selector> --prefix` to see all replicas
  during a rollout.
- **OIDC client secrets are a matched pair from one `authelia crypto hash generate` run** — the
  *plaintext* goes to the client (app), the *digest* goes to Authelia's client config. Regenerating
  means updating **both** sides; updating only one gives a generic `invalid_client` at the token
  exchange (the browser redirect still works, so it looks fine until the invisible server-side call
  fails). Also mind `token_endpoint_auth_method` matching on both ends (`client_secret_post` vs
  `client_secret_basic`).
- **`kubectl apply` reporting `unchanged` when you expected a change means your edit didn't save** —
  a surprisingly common cause of "I fixed it but nothing happened." Verify the file was written.
- **Nextcloud blocks outbound requests to private IPs by default** (SSRF protection). Reaching an
  internal service (e.g. Authelia at `10.1.1.200`) fails with "violates local access rules" until you
  set `occ config:system:set allow_local_remote_servers --value=true`. `curl` from the container
  works fine — it's a Nextcloud-specific guard, so the error only shows in Nextcloud's log.
- **Install Nextcloud apps via `occ app:install`, not the web UI** — the app-store UI can return an
  opaque `403` (session/permission quirk); the CLI just works and gives real errors.
- **`user_oidc` hashes the username by default** (`uniqueUid: true`) — you get a GUID user ID instead
  of the real name. Set `--unique-uid=0` (and `--mapping-uid=preferred_username`) for clean
  usernames. This is OIDC's opaque `sub` at work; pgAdmin shows the same GUID for the same reason.
- **Nextcloud brute-force throttling attributes attempts to the IP it *sees*** — behind a proxy that
  can be the proxy's container IP, not the real client (even with `trusted_proxies` set). Find the
  real one with `occ log:tail | grep "Remote IP"`, then `occ security:bruteforce:reset <ip>`.
  Successful logins don't clear an existing throttle window.
- **OnlyOffice rides Nextcloud's auth** — never put an auth proxy in front of the Document Server; it
  authenticates to Nextcloud via a shared JWT (`jwt_secret` must match on both sides), independent of
  how users log in.
- **Don't run OnlyOffice Document Server on `:latest` + `AutoUpdate=registry`** — a container restart
  silently upgrades it and can break the Nextcloud connector integration. Pin the version like
  everything else. (Its `/healthcheck` endpoint returning `true` confirms the server itself is fine.)
- **Client-side content blockers can break OnlyOffice** — uBlock/Ghostery false-positive-block the
  editor's `Analytics.js` (blocked by *filename*, not because it's a tracker). Symptom: editor spins
  forever; Network tab shows the asset "Stalled" and `ERR_FAILED` while `curl` gets `200`. That
  combination (**Stalled + curl works**) always means a *client-side* block, not a server problem.
  Ghostery's per-site pause doesn't override its network-layer rule; allowlist or remove it.
- **Argo only sees what's pushed to the git *remote*** — local commits (or uncommitted working-tree
  changes) are invisible to Argo. "I fixed it but Argo didn't pick it up" almost always = forgot to
  push. With auto-sync + self-heal on, an *uncommitted* local change also means a change you want
  live won't apply until pushed (and self-heal may revert manual `kubectl` changes to match git).
- **Sealing a secret whose name already exists** (manually created) fails: the SealedSecrets
  controller won't adopt a secret it didn't create (`already exists and is not managed by
  SealedSecret`). Fix: `kubectl delete secret <name>` so the controller can create its own. AND — the
  controller *gives up* after retries and won't re-try on an unchanged spec, so after deleting the
  manual secret you must **delete + recreate the SealedSecret CR** to force a fresh reconcile (a plain
  re-apply of the same spec is a no-op).
- **Large CRDs need `ServerSideApply=true`** — kube-prometheus-stack's Prometheus-operator CRDs
  exceed the 256KB annotation limit that client-side apply uses (`last-applied-configuration`), so the
  sync fails with `metadata.annotations: Too long`. Set `ServerSideApply=true` on that Application.
- **Gateway API HTTPRoutes show phantom diffs under ServerSideApply** — the API server defaults
  optional fields (`parentRefs[].group/kind`, `backendRefs[].group/kind/weight`) that SSA surfaces as
  drift. Add `ignoreDifferences` (jqPathExpressions) for those fields on any SSA app managing routes.
- **CNPG under Argo needs `ignoreDifferences`** — CNPG mutates the `Cluster` resource heavily
  (`.status`, `.spec.instances` on failover) and normalizes defaulted fields
  (`managed.roles[].connectionLimit/inherit`, `plugins[].enabled`), all of which show as perpetual
  drift unless ignored.
- **Sealed Secrets master key is the crown jewel** — it decrypts every SealedSecret. Back it up
  off-cluster (password manager), never in git. Lose it and all committed SealedSecrets are
  unrecoverable without re-sealing from plaintext.

---

## Incident lessons / recovery playbook

Hard-won from a real total outage (all pods unschedulable, every service down) triggered while
applying a Talos config change. Written up because these are the failures that are painful to
re-diagnose under pressure.

### The catastrophic one: `allowSchedulingOnControlPlanes`

**All nodes are control-plane. If `cluster.allowSchedulingOnControlPlanes: true` is dropped from the
config, Talos re-applies the `node-role.kubernetes.io/control-plane:NoSchedule` taint to every node,
and nothing can schedule — a full outage.** It's easy to lose when regenerating/editing configs (it
lives as a *commented example* in generated configs).

- **Symptom:** every non-system pod `Pending` with `FailedScheduling ... untolerated taint(s)`.
  System pods (Cilium, control-plane) keep running because they tolerate all taints, which masks the
  cause — the cluster looks half-up.
- **Diagnose:** `kubectl get nodes -o custom-columns='NODE:.metadata.name,TAINTS:.spec.taints'` —
  if you see `control-plane:NoSchedule` on every node, this is it.
- **Fix:** ensure `allowSchedulingOnControlPlanes: true` under `cluster:` in every node's config
  (and `common.yaml`), `talosctl apply-config` to all nodes. Talos removes the taint and everything
  schedules on its own.
- **Prevention:** this setting is load-bearing — keep it in `common.yaml` so config regeneration
  can't silently drop it.

### CNPG replica timeline divergence after multi-node reboot

Rebooting all nodes can promote/demote the Postgres primary several times, incrementing the
replication **timeline**. A replica can get stranded on an old timeline whose WAL diverged from the
new primary and crashloop.

- **Symptom:** one `pg-N` pod `CrashLoopBackOff`; logs show `record with incorrect prev-link ...`,
  `primary server contains no more WAL on requested timeline N`, `Refusing to restore future
  timeline history file`.
- **Fix (safe — it's a replica, holds no unique data):** delete that instance's PVC and pod; CNPG
  re-clones it fresh from the healthy primary:
  ```
  kubectl -n default delete pvc pg-N --wait=false && kubectl -n default delete pod pg-N
  ```
  Watch `kubectl get cluster pg -w` return to `3/3`. Confirm the primary has your data first
  (`psql -c '\l'`), so you know the clone source is good.

### Talos kubelet cert: metrics-server AND Prometheus scrapes

**The Talos kubelet's serving cert has no node-IP SAN** — its default self-signed cert carries only
`DNS:<nodename>` (e.g. `DNS:rpi-1`), not the node IP. Anything that scrapes the kubelet **by IP**
(`https://10.1.1.x:10250`) with TLS verification on fails with `x509: cannot validate certificate
for <ip> because it doesn't contain any IP SANs`. This bit **both** metrics-server and Prometheus.

- **This is not fixed by kubelet serving-cert rotation.** We tried `rotate-server-certificates` +
  the [cert-approver](https://github.com/alex1989hu/kubelet-serving-cert-approver): the rotated
  (cluster-CA-signed) cert *also* lacked an IP SAN, so verification still failed — just with a
  different issuer. Rotation delivered no benefit and added complexity, so it was **reverted**. The
  pragmatic, standard answer is to skip verification for kubelet scrapes.
- **metrics-server:** install with `--kubelet-insecure-tls`
  (`helm ... --set 'args={--kubelet-insecure-tls}'`). Encrypted, unverified — fine on a trusted LAN.
- **Prometheus (kube-prometheus-stack):** the kubelet `ServiceMonitor` needs BOTH
  `tlsConfig.insecureSkipVerify: true` AND bearer-token auth (`authorization` / the SA token) — the
  kubelet returns `401` if scraped without a token. Set these via
  `kubelet.serviceMonitor.tlsConfig.insecureSkipVerify: true` in the chart values (note the
  `tlsConfig.` nesting — the un-nested key is stale and silently doesn't render). A clean chart
  install renders the auth block automatically; a *drifted* release had lost it, causing the 401.
- **Debugging order that cracked it:** the scrape error walked `IP-SAN TLS failure` → (after
  skip-verify) `401 Unauthorized` → (after adding token) `up`. Each error pointed to the next fix.
  Lesson: with kubelet scrapes, expect to handle *both* TLS-skip and token auth.

### Post-recovery load imbalance

When a taint clears and everything schedules at once, the scheduler can pack most single-replica
Deployments onto one node. Symptom: the busiest node's pods fail readiness (e.g. an Alloy agent
starved of CPU can't bind its port before the probe times out — `2/3` DaemonSet, one pod `1/2` with
`connection refused` on the readiness probe, always the same node). `kubectl top nodes` shows that
node much hotter than the others. A rollout restart (or deleting the packed node's heavier pods to
let them reschedule) rebalances; Kubernetes does not auto-rebalance on its own.

### General recovery order

Diagnose top-down: **nodes Ready → Cilium/CNI healthy → taints/scheduling → per-workload**. Most
"everything is down" situations are one layer (CNI or a taint), not N broken services. The pile of
`Failed`/`Unknown` pods after an incident is mostly stale ReplicaSet corpses — sweep with
`kubectl delete pods -A --field-selector=status.phase=Failed` once the real cause is fixed.

---

## Updating components

**Under GitOps, updating means editing a manifest/values file, committing, and pushing** — Argo
reconciles the change (auto-sync for most apps; **manual sync for CNPG**, so bump the Postgres image
then sync the `cnpg` app deliberately). Every workload uses a **pinned image/chart version** (never
`:latest`), so updates are explicit and rollback = revert the git commit. Version numbers live in the
Helm values files (chart `targetRevision` in the `apps/*.yaml`) or the manifest image tags.

The pre-GitOps `helm upgrade`/`kubectl apply` mechanics below are retained as reference for what each
component *is*, but the day-to-day path is now **git push → Argo reconcile**:

| Component | Type | Where the version lives |
|---|---|---|
| CloudNativePG **operator** | Helm | `helm repo update && helm upgrade cnpg cnpg/cloudnative-pg -n cnpg-system` |
| **PostgreSQL version** (the database) | CNPG `Cluster` resource | Edit `imageName` in `pg-cluster.yaml`, apply — CNPG does a rolling update (replicas first, then a switchover) |
| cert-manager | Helm | `helm upgrade cert-manager jetstack/cert-manager -n cert-manager` (preserve custom `extraArgs` — see TLS note) |
| kube-prometheus-stack | Helm | `helm repo update && helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring -f kube-prometheus-stack-values.yaml` |
| metrics-server | Helm | `helm upgrade metrics-server metrics-server/metrics-server -n kube-system --set 'args={--kubelet-insecure-tls}'` |
| Loki | Helm | `helm upgrade loki grafana-community/loki -n loki -f loki-values.yaml` (real values file, not the example) |
| Alloy | Helm | `helm upgrade alloy grafana/alloy -n alloy -f alloy-values.yaml` |
| Technitium, LLDAP, Authelia, Valkey | plain Deployment / DaemonSet | Edit the image tag in the manifest, `kubectl apply`, watch `kubectl rollout status` |

**Safe update pattern for stateful components:**

1. **Read the release notes** — especially for major version bumps (breaking changes, migrations).
2. **Back up first** — CNPG backup for Postgres; Settings → Backup export for Technitium.
3. **Bump the pinned tag** in the manifest (keep it explicit).
4. **Apply and watch the rollout** (`kubectl rollout status`, check logs).
5. **Verify**, and roll back if needed (`kubectl rollout undo`, re-apply the old tag, or restore a backup).
6. **Commit** the version bump so the repo matches reality.

**Notes:**

- **Postgres minor** bumps (18.1 → 18.2) are safe rolling updates. **Major** bumps (18 → 19)
  involve a real migration — read the CNPG release notes first.
- **Do NOT try to grow Postgres storage in place on local-path.** Bumping `spec.storage.size`
  makes CNPG attempt a PVC resize, which local-path rejects — this *wedges the operator's reconcile
  loop* (it errors every cycle and stops managing the cluster), and the validation webhook then
  refuses to let you shrink the value back. The only reliable way to change storage size on
  local-path is: **back up (`pg_dumpall`) → delete the `Cluster` and its PVCs → recreate at the new
  size → restore the dump.** New PVCs provision at the new size with no resize involved. (Or migrate
  to Longhorn, after which a `size:` bump works normally.)
- **Technitium is a cluster** — keep the primary (optiplex quadlet) and the k8s secondaries on
  **matching versions**; update them together to avoid version skew.
- Finding new versions is manual (Docker Hub / GitHub releases, or `helm search repo <chart>
  --versions`). Tools like [Renovate](https://github.com/renovatebot/renovate) or
  [Diun](https://crazymax.dev/diun/) can watch for new tags and notify — optional for a homelab
  this size.
- **Always `helm upgrade -f <values-file>`; never `--reuse-values`.** `--reuse-values` keeps values
  only in cluster state, so the committed file stops matching reality (repo drift). Every Helm
  release here has a committed values file — pass it explicitly on every upgrade so the file stays
  authoritative. (Reconciled 2026-09-17 after `--reuse-values` had caused drift; verified each file
  produces a no-op upgrade against the live release.)
- **Watch for renamed values keys on chart major bumps.** kube-prometheus-stack moved
  `kubelet.serviceMonitor.insecureSkipVerify` → `kubelet.serviceMonitor.tlsConfig.insecureSkipVerify`;
  the old key silently stops rendering (no error), which is how the kubelet scrape TLS config went
  missing. Re-read the chart's values on major upgrades.

---

## Deferred / future work

Known items intentionally not done yet, captured so they aren't forgotten:

- **GitOps (Argo CD)** — ✅ **DONE (2026-09-19).** Entire cluster migrated to Argo CD with the
  app-of-apps pattern; secrets sealed into git via Sealed Secrets; auto-sync + self-heal on all apps
  except CNPG (manual, for database safety). Git is now the source of truth — the drift class that
  caused the outage and the `--reuse-values` divergence is structurally prevented. See the
  [GitOps section](#gitops-argo-cd).
- **Finish the cluster-recreate runbook** — the [GitOps bootstrap order](#gitops-argo-cd) covers the
  sequence (Talos → Cilium → Argo → Sealed Secrets + restore master key → create not-in-git secrets →
  apply root app). Still worth writing as one explicit, *tested* step-by-step runbook (and actually
  rehearsing it), plus confirming the list of not-in-git secrets is complete.
- **Grafana dashboards as code** — the hand-built dashboards live only in Grafana's ephemeral
  storage and are lost on a monitoring-stack reinstall. Provision them from labelled ConfigMaps
  (`grafana_dashboard: "1"`) committed to git so they survive reinstalls (and so they're GitOps-managed
  like everything else).
- **Re-test restores periodically** — a full restore was validated 2026-09-01 (see Backups). Repeat
  every few months, since a backup pipeline can break silently; consider a calendar reminder.
- **Longhorn** (or another expansion-capable provisioner) — for storage that survives node loss and
  supports in-place PVC resize (avoids the recreate-and-restore dance local-path forces). Justified
  once a single-instance, non-self-replicating stateful app is deployed.
- **Cilium NetworkPolicies** — lock down who can reach Postgres (`.202`) and other services.
- **TOTP 2FA + group-based authorization in Authelia** — enroll 2FA (via the `notification.txt`
  link, no SMTP) and gate services by LLDAP group (`admins` / `family`).
- **Migrate remaining optiplex services into the cluster** and retire NPM.

---

## Repository layout

```
hosts/talos/                        # Talos NODE config (managed by talosctl, NOT Argo)
├── common.yaml                     # shared Talos patch (incl. allowSchedulingOnControlPlanes!)
├── controlplane-rpi-{1,2,3}.yaml   # per-node configs (GITIGNORED — embed secrets)
├── controlplane.yaml, worker.yaml  # base configs (GITIGNORED)
└── apply.sh, build-talos-rpi-image.sh, rpi-schematic.yaml   # image/apply tooling

clusters/rpi-cluster/               # everything INSIDE the cluster (Argo's domain)
├── bootstrap/
│   ├── argocd-values.yaml          # Argo CD Helm values (server.insecure — TLS at Gateway)
│   └── argocd-route.yaml           # Argo CD HTTPRoute (argocd.fivelabs.tech)
├── root/
│   └── root-app.yaml               # app-of-apps root (watches apps/)
├── apps/                           # one Argo Application per component
│   ├── networking.yaml  storage.yaml  dns.yaml  cert-manager.yaml
│   ├── identity.yaml  sealed-secrets.yaml  loki.yaml  alloy.yaml
│   ├── monitoring.yaml             # (ServerSideApply + HTTPRoute ignoreDifferences)
│   └── cnpg.yaml                   # (MANUAL sync, Prune=false, ignoreDifferences)
└── manifests/                      # actual k8s YAML + Helm values, per component
    ├── networking/   gateway.yaml, cilium-lb.yaml, fivelabs-redirect.yaml
    ├── storage/      kustomization.yaml (local-path-provisioner)
    ├── dns/          technitium.yaml
    ├── cert-manager/ letsencrypt-issuers.yaml, fivelabs-cert*.yaml
    ├── identity/     lldap.yaml, authelia.yaml, authelia-config.yaml, valkey.yaml
    ├── cnpg/         pg-cluster.yaml (Delete=false), pg-lb, pg-objectstore,
    │                 pg-scheduledbackup, {lldap,authelia}-database.yaml,
    │                 minio-backup-sealedsecret.yaml
    ├── monitoring/   kube-prometheus-stack-values.yaml, grafana-route.yaml,
    │                 grafana-oidc-sealedsecret.yaml, grafana-admin-sealedsecret.yaml
    ├── loki/         loki-values.yaml, loki-route.yaml, loki-s3-sealedsecret.yaml
    └── alloy/        alloy-values.yaml
```

**Not in git (by design):** Talos node configs (`controlplane-rpi-*.yaml`, `secrets.yaml`,
`talosconfig`, `kubeconfig`), and the Sealed Secrets **master key** (backed up in the password
manager). Application secrets ARE in git — encrypted as SealedSecrets. CNPG-generated secrets
(`pg-app`, `pg-superuser`, TLS certs, `*-db-app`) are created by the operator, not stored anywhere.

---

*Built and documented as a learning project. Managed via GitOps (Argo CD). Talos node configs and the
Sealed Secrets master key are intentionally excluded from version control.*