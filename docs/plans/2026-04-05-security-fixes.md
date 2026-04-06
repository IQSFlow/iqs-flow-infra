# Security Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 9 security audit findings across 5 Terraform files to harden Cloud SQL, IAM, storage, monitoring, and Cloud Run.

**Architecture:** All changes are Terraform config edits in `iqs-flow-infra`. No application code changes. Single branch, single `terraform plan` validation at the end.

**Tech Stack:** Terraform 1.11.4, Google Cloud Provider ~> 5.0, GCS backend

**Setup:** `export PATH="/c/Users/joshu/bin:$PATH"` before any terraform commands.

---

### Task 1: Create branch

**Step 1: Create and checkout branch**

```bash
git checkout -b claude/security-fixes
```

**Step 2: Verify clean state**

```bash
git status
```

Expected: clean working tree on `claude/security-fixes`

---

### Task 2: Cloud SQL — disable public IP, enforce SSL, enable PITR (SEC-INFRA-001, 002, 007)

**Files:**
- Modify: `cloud-sql.tf:12-18`

**Step 1: Edit `cloud-sql.tf` ip_configuration block**

Replace the existing `ip_configuration` block:

```hcl
    ip_configuration {
      ipv4_enabled = true
    }
```

With:

```hcl
    ip_configuration {
      ipv4_enabled = false
      ssl_mode     = "ENCRYPTED_ONLY"
    }
```

**Step 2: Edit `cloud-sql.tf` backup_configuration block**

Replace:

```hcl
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = false
      start_time                     = "03:00"
    }
```

With:

```hcl
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
    }
```

**Step 3: Commit**

```bash
git add cloud-sql.tf
git commit -m "fix(security): disable Cloud SQL public IP, enforce SSL, enable PITR

SEC-INFRA-001: ipv4_enabled = false (Cloud Run uses Auth Proxy)
SEC-INFRA-002: ssl_mode = ENCRYPTED_ONLY
SEC-INFRA-007: point_in_time_recovery_enabled = true"
```

---

### Task 3: Storage — remove public bucket access (SEC-INFRA-004)

**Files:**
- Modify: `storage.tf:31-35`

**Step 1: Delete the `public_read` resource**

Remove this entire block from `storage.tf`:

```hcl
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
```

**Step 2: Commit**

```bash
git add storage.tf
git commit -m "fix(security): remove public access from uploads bucket

SEC-INFRA-004: Remove allUsers objectViewer binding.
API will serve files via signed URLs (tracked separately)."
```

---

### Task 4: IAM — scope serviceAccountUser to specific SAs (SEC-INFRA-005)

**Files:**
- Modify: `iam.tf:69-73`

**Step 1: Replace project-level `build_sa_user` with SA-level bindings**

Remove this block:

```hcl
resource "google_project_iam_member" "build_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.build.email}"
}
```

Replace with two SA-level bindings:

```hcl
resource "google_service_account_iam_member" "build_act_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.build.email}"
}

resource "google_service_account_iam_member" "build_act_as_web" {
  service_account_id = google_service_account.web.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.build.email}"
}
```

**Step 2: Commit**

```bash
git add iam.tf
git commit -m "fix(security): scope build SA serviceAccountUser to api+web SAs only

SEC-INFRA-005: Replace project-level iam.serviceAccountUser with
SA-level bindings on api and web service accounts."
```

---

### Task 5: IAM — scope run.developer to specific services (SEC-INFRA-006)

**Files:**
- Modify: `iam.tf:57-61`

**Step 1: Replace project-level `build_run` with service-level bindings**

Remove this block:

```hcl
resource "google_project_iam_member" "build_run" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.build.email}"
}
```

Replace with two Cloud Run service-level bindings:

```hcl
resource "google_cloud_run_v2_service_iam_member" "build_deploy_api" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.build.email}"
}

resource "google_cloud_run_v2_service_iam_member" "build_deploy_web" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.build.email}"
}
```

**Step 2: Commit**

```bash
git add iam.tf
git commit -m "fix(security): scope build SA run.developer to api+web services only

SEC-INFRA-006: Replace project-level run.developer with service-level
bindings on iqs-flow-api and iqs-flow-web Cloud Run services."
```

---

### Task 6: Monitoring — add notification channel and wire alerts (SEC-INFRA-009)

**Files:**
- Modify: `monitoring.tf` (add resource at top, update 4 alert policies)

**Step 1: Add email notification channel at the top of `monitoring.tf`**

Add before the first `google_monitoring_alert_policy`:

```hcl
resource "google_monitoring_notification_channel" "email" {
  display_name = "IQS Flow Admin Email"
  type         = "email"

  labels = {
    email_address = "jhinton@iqsflow.com"
  }
}
```

**Step 2: Wire notification channel into all 4 alert policies**

In each of the 4 `google_monitoring_alert_policy` resources, replace:

```hcl
  notification_channels = []
```

With:

```hcl
  notification_channels = [google_monitoring_notification_channel.email.name]
```

The 4 policies are:
- `api_errors` (line 21)
- `db_connections` (line 48)
- `api_downtime` (line 117)
- `api_high_error_rate` (line 148)

**Step 3: Commit**

```bash
git add monitoring.tf
git commit -m "fix(security): add email notification channel to all alert policies

SEC-INFRA-009: Create email notification channel (jhinton@iqsflow.com)
and wire it into all 4 monitoring alert policies."
```

---

### Task 7: Cloud Run — document image tag lifecycle, move SMTP_USER to secret (SEC-INFRA-011, 014)

**Files:**
- Modify: `cloud-run.tf:21,126`
- Modify: `secrets.tf` (add new secret)

**Step 1: Add comment documenting image tag on API service**

In `cloud-run.tf`, above the API container image line (line 21), add a comment:

```hcl
      # Image tag is managed by Cloud Build triggers, not Terraform.
      # lifecycle.ignore_changes prevents Terraform from reverting deployments.
      image = "${var.region}-docker.pkg.dev/${var.project_id}/iqs-flow/iqs-flow-api:latest"
```

**Step 2: Add same comment on Web service**

In `cloud-run.tf`, above the Web container image line (line 126), add same comment:

```hcl
      # Image tag is managed by Cloud Build triggers, not Terraform.
      # lifecycle.ignore_changes prevents Terraform from reverting deployments.
      image = "${var.region}-docker.pkg.dev/${var.project_id}/iqs-flow/iqs-flow-web:latest"
```

**Step 3: Add SMTP_USER secret to `secrets.tf`**

Add at the end of `secrets.tf`, before the comment:

```hcl
resource "google_secret_manager_secret" "smtp_user" {
  secret_id = "iqs-flow-smtp-user"
  replication {
    auto {}
  }
}
```

**Step 4: Replace plaintext SMTP_USER env with secret reference in `cloud-run.tf`**

Replace:

```hcl
      env {
        name  = "SMTP_USER"
        value = "info@iqsflow.com"
      }
```

With:

```hcl
      env {
        name = "SMTP_USER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.smtp_user.secret_id
            version = "latest"
          }
        }
      }
```

**Step 5: Commit**

```bash
git add cloud-run.tf secrets.tf
git commit -m "fix(security): move SMTP_USER to Secret Manager, document image lifecycle

SEC-INFRA-011: Add comments explaining image tag + lifecycle.ignore_changes.
SEC-INFRA-014: SMTP_USER now references Secret Manager instead of plaintext.
NOTE: Set secret value via: echo -n 'info@iqsflow.com' | gcloud secrets versions add iqs-flow-smtp-user --data-file=-"
```

---

### Task 8: Validate with terraform plan

**Step 1: Initialize terraform**

```bash
export PATH="/c/Users/joshu/bin:$PATH"
terraform init
```

**Step 2: Run terraform plan**

```bash
terraform plan
```

**Expected changes:**
- `google_sql_database_instance.main` — update in-place (ip_configuration, backup_configuration)
- `google_storage_bucket_iam_member.public_read` — destroy
- `google_project_iam_member.build_sa_user` — destroy
- `google_project_iam_member.build_run` — destroy
- `google_service_account_iam_member.build_act_as_api` — create
- `google_service_account_iam_member.build_act_as_web` — create
- `google_cloud_run_v2_service_iam_member.build_deploy_api` — create
- `google_cloud_run_v2_service_iam_member.build_deploy_web` — create
- `google_monitoring_notification_channel.email` — create
- 4x `google_monitoring_alert_policy.*` — update in-place (notification_channels)
- `google_secret_manager_secret.smtp_user` — create
- `google_cloud_run_v2_service.api` — update in-place (SMTP_USER env)

**CRITICAL CHECK:** Verify plan does NOT show destroy on `google_cloud_run_v2_service.api`, `google_cloud_run_v2_service.web`, or `google_sql_database_instance.main`.

**Step 3: Commit any formatting changes from init**

If `terraform fmt` changed anything during init, commit those too.

---

### Task 9: Mark task file as done

**Step 1: Rename task file**

```bash
mv .claude/tasks/security-fixes.md .claude/tasks/security-fixes.done.md
```

**Step 2: Final commit**

```bash
git add .claude/tasks/security-fixes.done.md .claude/tasks/security-fixes.md docs/plans/
git commit -m "chore: mark security-fixes task complete, add plan docs"
```

---

## Post-apply follow-up (manual)

After `terraform apply` succeeds:

1. Set SMTP_USER secret value:
   ```bash
   echo -n "info@iqsflow.com" | gcloud secrets versions add iqs-flow-smtp-user --data-file=-
   ```

2. Track signed-URL endpoint work in `iqs-flow-api` (new issue).
