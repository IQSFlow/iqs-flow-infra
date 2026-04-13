# Task: Terraform Workspace-Based Environment Split (Dev/Prod)

**Repo:** iqs-flow-infra
**Branch:** claude/env-split-workspaces
**Plan ref:** Phase 1, Tasks 1-3 (revised)

## CRITICAL CONTEXT

The previous approach (renaming resources with `-${var.environment}` suffix) would **destroy the production database and uploads bucket** because GCP resource names are immutable. Terraform would destroy+recreate them.

**The correct approach is Terraform Workspaces:**
- `default` workspace = current "dev" infra (UNTOUCHED, zero changes to existing resources)
- `prod` workspace = new production infra (fresh resources, separate state file)

This means **two separate Terraform state files** in the same GCS bucket, each managing its own set of GCP resources. The existing infra stays exactly as it is.

## What This Task Does

1. Update `main.tf` backend to support workspace-prefixed state
2. Add `environment` variable that defaults based on workspace name
3. Parameterize resource names with `local.env_suffix` (only affects NEW resources in prod workspace)
4. Add `environments/dev.tfvars` and `environments/prod.tfvars`
5. Add env-specific Cloud Run env vars (NEXT_PUBLIC_ENV, CORS_ORIGINS, APP_ENV)
6. Update dns.tf documentation

## What This Task Does NOT Do

- Does NOT rename any existing resources
- Does NOT run `terraform apply`
- Does NOT create the prod workspace (user does that manually)
- Does NOT touch the default workspace state at all

## Files

- Modify: `main.tf` -- workspace-aware backend prefix
- Modify: `variables.tf` -- add `environment` variable
- Create: `locals.tf` -- derive env_suffix from workspace
- Modify: `cloud-run.tf` -- parameterize service names, add env vars
- Modify: `cloud-sql.tf` -- parameterize instance name
- Modify: `secrets.tf` -- parameterize secret names
- Modify: `storage.tf` -- parameterize bucket name
- Modify: `cloud-tasks.tf` -- parameterize queue names
- Modify: `scheduler.tf` -- parameterize job names
- Modify: `pubsub.tf` -- parameterize topic/sub names
- Modify: `cloud-build.tf` -- parameterize trigger names
- Modify: `monitoring.tf` -- parameterize display names
- Modify: `dns.tf` -- update docs
- Create: `environments/dev.tfvars`
- Create: `environments/prod.tfvars`

## Implementation

### main.tf

Change the backend prefix to be workspace-aware. Terraform workspaces automatically namespace the state file, but we make it explicit:

```hcl
terraform {
  required_version = ">= 1.5"

  backend "gcs" {
    bucket = "iqs-flow-terraform-state"
    prefix = "terraform/state"
    # Workspaces create sub-paths automatically:
    #   default  -> terraform/state/default.tfstate
    #   prod     -> terraform/state/prod.tfstate
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}
```

No actual changes needed to the backend block -- Terraform handles workspace state isolation automatically.

### locals.tf (NEW FILE)

```hcl
locals {
  # "default" workspace = dev (no suffix, preserves existing resource names)
  # "prod" workspace = production (gets "-prod" suffix on all resources)
  is_prod    = terraform.workspace == "prod"
  env_suffix = local.is_prod ? "-prod" : ""
  env_label  = local.is_prod ? "prod" : "dev"
}
```

**KEY DESIGN:** The default workspace gets NO suffix. This means existing resources (`iqs-flow-api`, `iqs-flow-db`, etc.) keep their current names. Only the prod workspace creates new resources with `-prod` suffix.

### variables.tf

Add the `environment` variable (keep all existing variables unchanged):

```hcl
variable "environment" {
  description = "Environment name, derived from workspace. Override via tfvars if needed."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "marketing_domain" {
  description = "Custom domain for marketing site"
  type        = string
  default     = "iqsflow.com"
}
```

### environments/dev.tfvars

```hcl
environment      = "dev"
api_domain       = "dev.api.iqsflow.com"
web_domain       = "dev.app.iqsflow.com"
marketing_domain = "dev.iqsflow.com"
db_tier          = "db-custom-1-3840"
```

### environments/prod.tfvars

```hcl
environment      = "prod"
api_domain       = "api.iqsflow.com"
web_domain       = "app.iqsflow.com"
marketing_domain = "iqsflow.com"
db_tier          = "db-custom-1-3840"
```

### cloud-run.tf

Replace hardcoded service names with suffixed versions:

```hcl
resource "google_cloud_run_v2_service" "api" {
  name     = "iqs-flow-api${local.env_suffix}"
  location = var.region
  # ... rest unchanged except add these env blocks to the API container:

  env {
    name  = "APP_ENV"
    value = local.env_label
  }

  env {
    name  = "CORS_ORIGINS"
    value = local.is_prod ? "https://app.iqsflow.com,https://iqsflow.com,https://www.iqsflow.com" : "https://dev.app.iqsflow.com,https://dev.api.iqsflow.com,http://localhost:3000"
  }
}

resource "google_cloud_run_v2_service" "web" {
  name     = "iqs-flow-web${local.env_suffix}"
  location = var.region
  # ... rest unchanged except add:

  env {
    name  = "NEXT_PUBLIC_ENV"
    value = local.env_label
  }
}

resource "google_cloud_run_v2_service" "marketing" {
  name     = "iqs-flow-marketing${local.env_suffix}"
  location = var.region
  # ... rest unchanged
}
```

Also parameterize the migrations job if it exists:
```hcl
name = "iqs-flow-migrations${local.env_suffix}"
```

### cloud-sql.tf

```hcl
resource "google_sql_database_instance" "main" {
  name             = "iqs-flow-db${local.env_suffix}"
  # ... rest unchanged
}
```

### secrets.tf

Suffix all secret IDs:
```hcl
resource "google_secret_manager_secret" "db_url" {
  secret_id = "iqs-flow-db-url${local.env_suffix}"
}
resource "google_secret_manager_secret" "session_secret" {
  secret_id = "iqs-flow-session-secret${local.env_suffix}"
}
# ... same pattern for smtp_pass, smtp_user, maps_key, aerodatabox_key, firebase_api_key
```

### storage.tf

```hcl
resource "google_storage_bucket" "uploads" {
  name = "${var.project_id}-iqs-flow-uploads${local.env_suffix}"
  # ... rest unchanged
}
```

### cloud-tasks.tf, scheduler.tf, pubsub.tf, cloud-build.tf

Same pattern -- append `${local.env_suffix}` to all resource names.

### monitoring.tf

Update display names:
```hcl
display_name = "API Latency (${local.env_label})"
```

Update filters to reference resource attributes instead of hardcoded service names.

### dns.tf

Update documentation only:
```hcl
# Domain Mappings (managed via gcloud, not Terraform)
#
# Production (workspace: prod):
#   app.iqsflow.com      -> iqs-flow-api-prod
#   api.iqsflow.com      -> iqs-flow-web-prod
#   iqsflow.com          -> iqs-flow-marketing-prod
#
# Development (workspace: default):
#   dev.app.iqsflow.com  -> iqs-flow-web  (no suffix, original names)
#   dev.api.iqsflow.com  -> iqs-flow-api  (no suffix, original names)
```

## How The User Will Use This

### First time setup (after merge):

```bash
# Verify default workspace still works (should be no-op / zero changes)
terraform workspace list
# * default

terraform plan -var-file=environments/dev.tfvars
# Should show: No changes. Infrastructure is up-to-date.
# (because default workspace = no suffix = existing resource names)

# Create and switch to prod workspace
terraform workspace new prod

# Plan prod (creates all new resources with -prod suffix)
terraform plan -var-file=environments/prod.tfvars
# Should show: 38 to add, 0 to change, 0 to destroy

# Apply prod
terraform apply -var-file=environments/prod.tfvars
```

### Day-to-day:

```bash
# Work on dev
terraform workspace select default
terraform plan -var-file=environments/dev.tfvars

# Work on prod
terraform workspace select prod
terraform plan -var-file=environments/prod.tfvars
```

## Verification

```bash
terraform fmt -recursive
terraform validate

# CRITICAL: verify default workspace shows NO changes (existing infra untouched)
terraform workspace select default
terraform plan -var-file=environments/dev.tfvars
# Expected: "No changes" or minimal non-destructive changes

# Verify prod workspace plans correctly
terraform workspace new prod
terraform plan -var-file=environments/prod.tfvars
# Expected: "X to add, 0 to change, 0 to destroy"
```

If default workspace shows ANY destroys or replacements, STOP. The suffixing logic is wrong.

## DO NOT

- Do NOT run `terraform apply`
- Do NOT rename existing resources in the default workspace
- Do NOT delete or move state
- Do NOT change the GCS backend bucket
