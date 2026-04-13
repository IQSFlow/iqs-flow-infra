# Done: Terraform Workspace-Based Environment Split

**Branch:** claude/env-split-workspaces
**Files changed:** 16 files

## What changed
- Added `locals.tf` deriving `env_suffix` / `env_label` from `terraform.workspace`.
- Parameterized all named resources (Cloud Run services + migration job, Cloud SQL, secrets, uploads bucket, Cloud Tasks queues, Scheduler jobs, Pub/Sub topics + subscription, Cloud Build triggers, monitoring display names + filters) with `${local.env_suffix}`.
- Added `environment` and `marketing_domain` variables; added `environments/dev.tfvars` + `environments/prod.tfvars`.
- Added `APP_ENV` + `CORS_ORIGINS` env vars to API Cloud Run, `NEXT_PUBLIC_ENV` to web Cloud Run.
- Updated `dns.tf` docs for dev/prod mapping layout.
- Whitelisted `environments/*.tfvars` in `.gitignore`.

## Verify
- `terraform fmt -recursive` clean (only reflowed cloud-sql.tf comment).
- `terraform validate` → "Success! The configuration is valid."
- Default workspace resource names unchanged (suffix is empty string). User must run `terraform plan -var-file=environments/dev.tfvars` in `default` workspace and confirm "No changes" before creating the `prod` workspace.

## Notes
- No `terraform apply` was run (per task).
- Monitoring filters now reference `google_cloud_run_v2_service.api.name` and `google_sql_database_instance.main.name` so they stay in sync with whichever workspace is active.
