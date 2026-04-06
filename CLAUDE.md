# IQS Flow Infra — Codebase Guide

> **Company:** Integrity Quality Solutions (IQS) | **Domain:** iqsflow.com
> **Repo:** `iqs-flow-infra` — Terraform IaC for all GCP infrastructure
> **Stack:** Terraform · Google Cloud Provider · GCS backend
> **GCP Project:** `crested-booking-488922-f7`

---

## Architecture (4-repo split + infra)

```
iqs-flow-api/       → REST API + Prisma + business logic         → Cloud Run
iqs-flow-web/       → Next.js dashboard (SSR frontend)            → Cloud Run
iqs-flow-mobile/    → Expo Android app (cleaners)                 → Play Store (EAS Build)
iqs-flow-shared/    → Zod schemas, constants, shared types        → npm package (Artifact Registry)
iqs-flow-infra/     → Terraform IaC for ALL GCP resources         ← THIS REPO
```

---

## What This Repo Manages

| File | Resources |
|------|-----------|
| `main.tf` | Provider, GCS backend, required providers |
| `cloud-run.tf` | API + Web Cloud Run services |
| `cloud-sql.tf` | PostgreSQL 15 instance, database, user |
| `secrets.tf` | Secret Manager secrets (values managed via gcloud) |
| `iam.tf` | 4 service accounts + IAM role bindings |
| `artifact-registry.tf` | Docker + npm repos |
| `cloud-build.tf` | 3 Cloud Build triggers (tag-based) |
| `dns.tf` | Domain mapping documentation (managed via gcloud) |
| `apis.tf` | All enabled GCP APIs |
| `scheduler.tf` | Cloud Scheduler cron jobs |
| `cloud-tasks.tf` | Async task queues |
| `monitoring.tf` | Alert policies |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values (URLs, connection names) |

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
- **Cloud Run images are managed by Cloud Build**, Terraform ignores image changes via lifecycle
- **Cloud SQL requires at least one connectivity method** — can't set `ipv4_enabled = false` without Private IP or PSC configured
- **Set secret values before referencing in Cloud Run** — create secret shell in TF, set value via gcloud, then apply Cloud Run changes

## Terraform State

- **Backend:** `gs://iqs-flow-terraform-state/terraform/state`
- **Versioning:** Enabled on the bucket
- **Lock:** Automatic via GCS

## Service Accounts

| Account | Used By | Roles |
|---------|---------|-------|
| `iqs-api@` | Cloud Run API | Cloud SQL Client, Secret Accessor |
| `iqs-web@` | Cloud Run Web | Secret Accessor |
| `iqs-build@` | Cloud Build | AR Writer, Run Developer (scoped to api+web services), Secret Accessor, SA User (scoped to api+web SAs), Log Writer |
| `iqs-scheduler@` | Cloud Scheduler | Run Invoker |

## GCP Project Details

| Field | Value |
|-------|-------|
| Project ID | `crested-booking-488922-f7` |
| Region | `us-central1` |
| Cloud SQL | `iqs-flow-db` (PostgreSQL 15) |
| Domains | `iqsflow.com` (web), `api.iqsflow.com` (API) |

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
- **NEVER push directly to `main`** — only push `claude/` branches
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

---

## Task Completion Checklist (MANDATORY)

1. Run `terraform plan` to verify changes
2. Run `terraform apply` only after plan review
3. Run `/sp-verification-before-completion` — verify with evidence
4. Run `/commit` — commit with clear message
5. Run `/revise-claude-md` — capture learnings
