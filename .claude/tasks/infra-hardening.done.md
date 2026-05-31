# Done: Infra Hardening (Cloud SQL, Cloud Run ingress, Scheduler, Monitoring)

**Branch:** claude/infra-hardening
**Base:** main (no `claude/infra-hardening` pre-existed; branched fresh off main)
**Files changed:** 6 (`cloud-sql.tf`, `cloud-run.tf`, `scheduler.tf`, `storage.tf`, `monitoring.tf`, `variables.tf`)

> Terraform written, NOT applied. No `terraform apply`, no deploy tags, no secret/tfvars edits.

## What changed

### Cloud SQL exposure (`cloud-sql.tf`, `variables.tf`)
- `ip_configuration` now parameterized BEHIND new variables that **default to current behavior** (public IPv4 stays on):
  - `db_ipv4_enabled` (default `true`) -> `ipv4_enabled`
  - `db_enable_private_ip` (default `false`) + `db_private_network` (default `""`) -> conditional `private_network`
  - `db_authorized_networks` (default `[]`) -> dynamic `authorized_networks` allowlist
- Added inert (`count = 0` by default) Private-IP scaffolding: `google_compute_global_address.private_ip_range` (VPC_PEERING /16) + `google_service_networking_connection.private_vpc_connection`, plus a conditional `depends_on` on the instance. Nothing materializes until the toggle flips, so applying this branch is a connectivity no-op.

### Cloud Run ingress (`cloud-run.tf`, `variables.tf`)
- Added `ingress = var.api_ingress` to the API service (default `INGRESS_TRAFFIC_ALL` = current behavior; validated enum allows `..._INTERNAL_LOAD_BALANCER`).
- Gated `api_public` (allUsers run.invoker) behind `var.api_allow_public_invoke` (default `true` = current behavior).
- Added inert companion `api_scheduler_invoke` (count flips on when public invoke is turned off) granting the scheduler SA explicit `run.invoker` so cron keeps working post-cutover.
- **Confirmed cron OIDC:** `iqs-flow-api/src/routes/cron.ts` `verifyCronAuth()` validates the Google OIDC token via `OAuth2Client.verifyIdToken` and allows only `iqs-scheduler@` / `iqs-api@` SAs (with a `CRON_SECRET` dev fallback). So even while the API is allUsers-invokable, cron/report/cleanup routes return 401 to anonymous callers. The in-app guard is the real protection today; LB/IAP fronting (the var path above) is defense-in-depth. The API-side fix is owned on a separate branch.

### Scheduler (`scheduler.tf`)
- Rewrote all jobs to use the **scheduler SA** (`iqs-scheduler@`) as OIDC identity — fixes the `daily_cleanup` identity bug (was the API SA at old line 44).
- Retargeted stale jobs from retired routes to current ones: `/api/health/cleanup` -> `/api/cron/cleanup`; `/api/reports/weekly` -> `/api/cron/weekly-digest`. Consolidated the duplicate cleanup (old `session_cleanup` + `daily_cleanup` both hit cleanup) into a single `daily_cleanup`.
- Added jobs for the other real `/api/cron/*` routes that exist in code but had no scheduler: `daily-digest`, `generate-daily-tasks`, `process-scheduled-tickets`, `gate-turns`, `sync-flights`, `process-pm-plans`, `compute-vas`. All target `google_cloud_run_v2_service.api.uri`.

### Storage CORS (`storage.tf`)
- Removed the wildcard `https://iqs-flow-web-*-uc.a.run.app` origin (GCS CORS doesn't honor wildcards anyway). Now an explicit per-env allowlist mirroring the API `CORS_ORIGINS`: prod = app/root/www iqsflow.com; dev = dev.app.iqsflow.com + localhost:3000.

### Monitoring (`monitoring.tf`)
- Fixed the two overlapping 5xx policies: renamed `api_errors` to "5xx Error Count" (it's a count, not a rate). Replaced the mislabeled `api_high_error_rate` (which used `ALIGN_SUM` count > 10 — a count masquerading as a rate, overlapping `api_errors`) with `api_5xx_ratio`, a genuine MQL ratio alert (5xx / total > 10% over 10m).
- Added `db_cpu` (>80%) and `db_disk` (>85%) Cloud SQL alert policies.
- Added `pubsub_dead_letter` alert (>0 messages into the `dead-letter` topic in 5m).

### Unused vars (`variables.tf`)
- Removed unused TF input variables `session_secret` and `smtp_pass`. They were never referenced by any `.tf` (the secret VALUES are managed via gcloud; the secret SHELLS and the runtime env vars `SESSION_SECRET`/`SMTP_PASS` are unaffected and still wired in `cloud-run.tf`).

## Verify
- `terraform fmt -check -recursive` -> exit 0 (clean).
- `terraform validate` -> "Success! The configuration is valid." (local binary is v1.11.4 at `/c/Users/joshu/bin`, which is >= the `required_version >= 1.5` in main.tf — the task brief mentioned a 1.2.6 binary, but the one on PATH per repo CLAUDE.md is 1.11.4, so validate ran cleanly against provider google 5.45.2. `terraform plan`/`apply` deliberately NOT run.)
- No changes to `terraform.tfvars`, secrets, Dockerfile, cloudbuild, or any other repo.

## Deferred / action items for the user
- **Cloud SQL Private-IP cutover (manual, sequenced):** (1) create/choose a VPC and set `db_private_network`; (2) ensure Service Networking API + peering; (3) wire a Serverless VPC Access connector into the API + migration-job Cloud Run (NOT done here — needs a `google_vpc_access_connector` and `vpc_access` block, deferred because it changes the live data path); (4) `db_enable_private_ip = true` and apply; (5) only after every client (Cloud Run, migration job, admin proxy) reaches the DB privately, set `db_ipv4_enabled = false`. Never disable IPv4 before Private IP is live (Cloud SQL needs >=1 connectivity method).
- **API ingress cutover:** stand up an external HTTPS LB (Cloud Armor / IAP) fronting `api.iqsflow.com`, then set `api_ingress = INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` and `api_allow_public_invoke = false`. Cut DNS first; flipping these without the LB returns 403 to the dashboard and cron.
- **`terraform.tfvars` cleanup (cannot edit per guardrails):** tfvars still has orphaned `session_secret` / `smtp_pass` entries. After this merges, remove those two lines from `terraform.tfvars` to clear the "value set for undeclared variable" *warning* (warning only — does not fail plan/apply). Those secret values are unchanged in Secret Manager.
- **Scheduler cron cadences** are best-effort from route comments in `cron.ts`; confirm desired times before applying (esp. `compute-vas`, `process-pm-plans`).
- Did NOT run `terraform plan`/`apply` (out of scope, branch-gated).
