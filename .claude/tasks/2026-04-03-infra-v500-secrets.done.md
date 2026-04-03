# Infra v5.0.0 — Missing Secrets + API Env Vars

> **Priority:** P1 — needed before v5.0.0 deployment
> **Branch:** `claude/v5-infra-secrets`
> **Isolation:** Use a git worktree (`isolation: "worktree"`) for this work so other agents aren't blocked.

## Required Skills
- `superpowers:verification-before-completion` — before claiming done
- `commit-commands:commit` — for each change

## Context
The API now uses AeroDataBox for flight sync and the web uses Google Maps. Both keys exist in GCP Secret Manager but are NOT managed by Terraform and NOT wired to Cloud Run.

## Task 1: Add missing secret resources to secrets.tf

Add these to `secrets.tf`:

```hcl
resource "google_secret_manager_secret" "google_maps_key" {
  secret_id = "google-maps-api-key"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "aerodatabox_key" {
  secret_id = "aerodatabox-api-key"
  replication {
    auto {}
  }
}
```

These secrets already exist in GCP — Terraform will need to import them:
```bash
terraform import google_secret_manager_secret.google_maps_key projects/crested-booking-488922-f7/secrets/google-maps-api-key
terraform import google_secret_manager_secret.aerodatabox_key projects/crested-booking-488922-f7/secrets/aerodatabox-api-key
```

**DO NOT run terraform import or terraform apply — just add the resource definitions. The user will import manually.**

## Task 2: Wire AERODATABOX_API_KEY env var on API Cloud Run service

In `cloud-run.tf`, find the `google_cloud_run_v2_service.api` resource. Inside the `containers` block, after the existing `env` blocks (DATABASE_URL, SESSION_SECRET, SMTP_PASS), add:

```hcl
      env {
        name = "AERODATABOX_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.aerodatabox_key.secret_id
            version = "latest"
          }
        }
      }
```

## Task 3: Add GCS bucket for tenant logo uploads

Create a new file `storage.tf` or add to an existing file:

```hcl
resource "google_storage_bucket" "uploads" {
  name          = "${var.project_id}-iqs-flow-uploads"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  cors {
    origin          = ["https://iqsflow.com", "https://www.iqsflow.com", "https://iqs-flow-web-*-uc.a.run.app"]
    method          = ["GET", "PUT", "POST"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }
}

# Grant the API service account write access
resource "google_storage_bucket_iam_member" "api_upload" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.api.email}"
}

# Grant public read access for logos (they need to be viewable in browsers)
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
```

Also add `GCS_BUCKET` env var to the API Cloud Run service:

```hcl
      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.uploads.name
      }
```

## After All Changes
```bash
terraform fmt    # format all .tf files
terraform validate  # must pass
```

**DO NOT run `terraform apply` — the user will review and apply manually.**

## Definition of Done
- `secrets.tf` has google-maps-api-key and aerodatabox-api-key resources
- `cloud-run.tf` API service has AERODATABOX_API_KEY and GCS_BUCKET env vars
- GCS bucket resource defined with CORS and IAM
- `terraform validate` passes
- Committed and pushed
