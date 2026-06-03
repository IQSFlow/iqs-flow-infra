# IQS Flow Infra — Codebase Guide

> **Company:** Integrity Quality Solutions (IQS) | **Domain:** iqsflow.com
> **Repo:** `iqs-flow-infra` — Terraform IaC for all GCP infrastructure
> **Stack:** Terraform · Google Cloud Provider · GCS backend
> **GCP Project:** `crested-booking-488922-f7`

---

## Architecture (7-repo workspace)

```
iqs-flow-shared/         → Zod schemas, constants, shared types   → npm package (Artifact Registry, @iqsflow/shared)
iqs-flow-api/            → Hono + Prisma REST API (port 4000)      → Cloud Run
iqs-flow-web/            → Next.js 15 dashboard + portals (3000)   → Cloud Run
iqs-flow-mobile/         → Expo Android app (cleaners)             → Play Store (EAS Build) + OTA
iqs-flow-infra/          → Terraform IaC for ALL GCP resources     ← THIS REPO
iqs-flow-marketing/      → Marketing site (iqsflow.com)            → Cloud Run (port 3000)
iqs-flow-design-handoff/ → Design assets / HTML→JSX handoff        → read-only reference (not a git repo)
```

**Dependency / wave order:** `shared → api → web + mobile`. Cross-boundary request/response
contracts live in `@iqsflow/shared`; consumers import them, never hand-roll inline Zod/TS.
This repo (`infra`) provisions the GCP substrate all of the above run on — it is LIVE in
production, not a plan.

---

## What This Repo Manages

| File | Resources |
|------|-----------|
| `main.tf` | Provider (`google` + `google-beta` `~> 5.0`), GCS backend, `required_version >= 1.5` |
| `cloud-run.tf` | API (4000) + Web (3000) + Marketing (3000) Cloud Run services, the `run-migrations` job, and public-invoke IAM (API public-invoke is gated behind `var.api_allow_public_invoke`) |
| `cloud-sql.tf` | PostgreSQL 15 instance + DB + user, plus inert Private-IP scaffolding (global address + service-networking connection, `count`-gated off by default) |
| `secrets.tf` | Secret Manager secret shells (values managed via gcloud): `db-url`, `session-secret`, `api-url`, `smtp-pass`, `smtp-user`, `google-maps-api-key`, `aerodatabox-api-key` (all suffixed `-prod` in the prod workspace) |
| `storage.tf` | GCS uploads bucket (UBLA on, per-env CORS allowlist, 365-day lifecycle) + API `objectAdmin` binding |
| `iam.tf` | 4 service accounts + IAM bindings. Build SA `run.developer` is scoped per-service (api/web/marketing) and `serviceAccountUser` is scoped per-SA, not project-wide |
| `pubsub.tf` | 7 topics + worker-location subscription (dead-letter policy) + API publisher/subscriber roles |
| `cloud-tasks.tf` | 2 async queues: `iqs-email-queue`, `iqs-reports-queue` |
| `artifact-registry.tf` | `iqs-flow` (Docker) + `iqs-flow-npm` (NPM) repos |
| `cloud-build.tf` | 3 tag-based triggers: api deploy, web deploy, shared publish (all `^v.*$`). Marketing/forms infra is provisioned by scripts, not a TF trigger |
| `dns.tf` | Domain-mapping documentation only (managed via gcloud — v1/v2 API mismatch) |
| `apis.tf` | All enabled GCP APIs (run, sqladmin, build, AR, secret manager, scheduler, tasks, gmail, maps, pubsub, error-reporting, …) |
| `scheduler.tf` | 11 Cloud Scheduler cron jobs hitting `/api/cron/*`, all OIDC-authed as the scheduler SA |
| `monitoring.tf` | Email notification channel, 2 uptime checks, 6 alert policies (5xx count, 5xx ratio, DB connections/CPU/disk, Pub/Sub dead-letter) |
| `variables.tf` | Input variables (incl. Cloud SQL network + Cloud Run ingress hardening toggles, all defaulting to current behavior) |
| `locals.tf` | Workspace-derived env suffix/label (`prod` workspace → `-prod`; `default` → dev, no suffix) |
| `outputs.tf` | Output values (API/Web URLs, DB connection name, SA emails) |

---

## Commands

| Command | What it does |
|---------|-------------|
| `terraform init` | Initialize providers + GCS backend |
| `terraform plan` | Preview changes (ALWAYS run before apply) |
| `terraform apply` | Apply changes to GCP |
| `terraform state list` | List all managed resources |
| `terraform import <resource> <id>` | Import existing GCP resource |

**CRITICAL:** Always run `terraform plan` before `terraform apply`. Never apply without reviewing the plan.

---

## Key Rules

- **NEVER destroy Cloud Run services, Cloud SQL, or secrets** without explicit approval
- **NEVER modify terraform.tfvars** — contains real passwords (gitignored)
- **NEVER commit .terraform/ or *.tfstate** — state lives in GCS bucket
- **Domain mappings are managed via gcloud**, not Terraform (v1/v2 API mismatch)
- **Secret VALUES are managed via gcloud**, Terraform only manages the secret shell
- **Cloud Run images are managed by Cloud Build**, Terraform ignores image changes via lifecycle (`api`, `web`, and the `run-migrations` job)
- **Cloud SQL requires at least one connectivity method** — connectivity is now variable-driven (`db_ipv4_enabled`, `db_enable_private_ip`, `db_private_network`, `db_authorized_networks`), all defaulting to current behavior (public IPv4 ON, SSL `ENCRYPTED_ONLY`). Private-IP scaffolding is inert (`count = 0`) until enabled. Never set `db_ipv4_enabled = false` before Private IP/PSC is live for every client. See `variables.tf` + `.claude/tasks/infra-hardening.done.md` for the cutover sequence.
- **API public-invoke + ingress are variable-driven** — `var.api_allow_public_invoke` (default `true`) grants `allUsers` run.invoker; `var.api_ingress` (default `INGRESS_TRAFFIC_ALL`) sets ingress. Cron routes are guarded today by the in-app OIDC check in `iqs-flow-api/src/routes/cron.ts`, not by Cloud Run IAM. Flipping these off requires fronting the API with an LB/IAP and granting the scheduler SA run.invoker, or the dashboard + cron get 403.
- **Set secret values before referencing in Cloud Run** — create secret shell in TF, set value via gcloud, then apply Cloud Run changes

## Terraform State

- **Backend:** `gs://iqs-flow-terraform-state/terraform/state`
- **Versioning:** Enabled on the bucket
- **Lock:** Automatic via GCS

## Workspaces (dev vs prod)

Dev and prod are the **same Terraform config** in two workspaces (see `locals.tf`):

- **`default` workspace = dev** — no suffix (`iqs-flow-api`, `iqs-flow-db`, `iqs-flow-db-url`, …). `APP_ENV=dev`.
- **`prod` workspace = production** — every resource name gets a `-prod` suffix (`iqs-flow-api-prod`, `iqs-flow-db-prod`, `iqs-flow-db-url-prod`, …). `APP_ENV=prod`.

```bash
terraform workspace list          # shows default + prod
terraform workspace select prod   # before planning/applying prod
terraform workspace select default
```

Per-environment input overrides live in `environments/dev.tfvars` and `environments/prod.tfvars`.

## How app deploys relate to this repo

This repo provisions the infra; **application code deploys are driven by git tags in the
api/web/shared repos**, not by `terraform apply`:

- `^v.*` tag on `iqs-flow-api` / `iqs-flow-web` → Cloud Build → DEV services (`iqs-flow-api` / `iqs-flow-web`).
- `^prod-v.*` tag → PROD services (`iqs-flow-api-prod` / `iqs-flow-web-prod`).
- `v*` tag on `iqs-flow-shared` → publishes `@iqsflow/shared` to the `iqs-flow-npm` Artifact Registry repo.

The Cloud Run image tag is `lifecycle.ignore_changes`-protected here, so Terraform never reverts a
Cloud Build deployment. Always dev-first, then prod. Don't poll Cloud Build (~5–7 min builds).

## Service Accounts

| Account | Used By | Roles |
|---------|---------|-------|
| `iqs-api@` | Cloud Run API + `run-migrations` job | Cloud SQL Client, Secret Accessor, Vertex AI User (`aiplatform.user`), Cloud Translation User (`cloudtranslate.user`), Pub/Sub Publisher + Subscriber, GCS `objectAdmin` on the uploads bucket |
| `iqs-web@` | Cloud Run Web **and Marketing** | Secret Accessor |
| `iqs-build@` | Cloud Build | AR Writer, Run Developer (scoped to api/web/marketing services), Secret Accessor, SA User (scoped to api+web SAs), Log Writer |
| `iqs-scheduler@` | Cloud Scheduler (OIDC identity on all 11 cron jobs) | Run Invoker |

## GCP Project Details

| Field | Value |
|-------|-------|
| Project ID | `crested-booking-488922-f7` |
| Region | `us-central1` |
| Cloud SQL | `iqs-flow-db` (dev) / `iqs-flow-db-prod` (prod), both PostgreSQL 15 |
| Prod domains | `iqsflow.com` → marketing, `app.iqsflow.com` → web, `api.iqsflow.com` → API |
| Dev domains | `dev.iqsflow.com` → marketing, `dev.app.iqsflow.com` → web, `dev.api.iqsflow.com` → API |

---

## Safety Guardrails — MANDATORY

### Filesystem
- **NEVER read/write/delete outside this repo** (`C:\Users\joshu\Flow\iqs-flow-infra\`)
- **NEVER modify** `.env`, `.env.local`, or files containing secrets
- **NEVER run** `rm -rf`, `git clean -f`, `git reset --hard`
- **NEVER run** `terraform destroy` without explicit user approval

### Terraform
- **ALWAYS run `terraform plan`** before `terraform apply`
- **NEVER apply** if plan shows destroy on Cloud Run, Cloud SQL, or secrets
- **Never force-push `main` or commit straight onto it.** Work on a `claude/<task>` branch; single-mode tasks then merge to `main` per the global `CLAUDE.md` autonomous flow. Tasks touching auth, migrations, or cross-tenant data stop at a pushed `claude/` branch for the Codex review gate.
- **Review all changes** in the plan output before applying

### When Unsure → Ask the user first

---

## Terraform Binary

Terraform v1.11.4 is installed at `/c/Users/joshu/bin/terraform`. Always set PATH:
```bash
export PATH="/c/Users/joshu/bin:$PATH"
```

## gcloud CLI

On Windows/MSYS2, direct `gcloud` calls fail with path translation. Use:
```bash
cmd //c "gcloud secrets versions add SECRET_NAME --data-file=- --project=crested-booking-488922-f7"
```

## Windows / PowerShell gotchas

- Use `py`, not `python3` (the bare `python3` is the Windows Store stub).
- PowerShell 5.1 has no `&&` / `||` chaining and no ternary — use `;` + `if ($?) { }`.
- Avoid unicode arrows / box-drawing chars inside `.sh`/`.sql`/HCL string literals (encoding breakage); they're fine in Markdown prose like this file.

---

## Task Completion Checklist (MANDATORY)

1. Run `terraform plan` to verify changes
2. Run `terraform apply` only after plan review
3. Run `/sp-verification-before-completion` — verify with evidence
4. Run `/commit` — commit with clear message
5. Run `/revise-claude-md` — capture learnings
