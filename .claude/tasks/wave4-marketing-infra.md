# Wave 4: Add marketing Cloud Run service and DNS

Work on branch `claude/marketing-infra`. Do NOT run `terraform apply`. Do NOT push.

If something is unclear, make the safe choice and note it in your commit message. Do NOT stop to ask questions.

Full plan: `C:/Users/joshu/Flow/iqs-flow-shared/docs/plans/2026-04-05-web-repo-split.md`

## Step 1: Add Cloud Run service for marketing

Add to `cloud-run.tf`:

```hcl
# Marketing website (iqsflow.com)
resource "google_cloud_run_v2_service" "marketing" {
  name     = "iqs-flow-marketing"
  location = var.region

  template {
    service_account = google_service_account.web.email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/iqs-flow/iqs-flow-marketing:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service_iam_member" "marketing_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.marketing.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

## Step 2: Add Cloud Build deploy permission for marketing

Add a scoped `roles/run.developer` IAM binding for the build SA on the marketing service (same pattern as api and web):

```hcl
resource "google_cloud_run_v2_service_iam_member" "build_deploy_marketing" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.marketing.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.build.email}"
}
```

## Step 3: Update dns.tf comment

```hcl
# Existing mappings:
#   iqsflow.com       -> iqs-flow-marketing  (marketing site)
#   app.iqsflow.com   -> iqs-flow-web        (authenticated portal)
#   api.iqsflow.com   -> iqs-flow-api
#
# Domain mapping commands (run manually after terraform apply):
#   gcloud beta run domain-mappings delete --service=iqs-flow-web --domain=iqsflow.com --region=us-central1
#   gcloud beta run domain-mappings create --service=iqs-flow-marketing --domain=iqsflow.com --region=us-central1
#   gcloud beta run domain-mappings create --service=iqs-flow-web --domain=app.iqsflow.com --region=us-central1
```

## Step 4: Run terraform plan

```bash
terraform plan
```

Include the plan summary in your done report. Do NOT run `terraform apply`.

## Step 5: Commit

```bash
git add cloud-run.tf dns.tf iam.tf
git commit -m "feat: add marketing Cloud Run service for web repo split"
```

## When done

Write `.claude/tasks/wave4-marketing-infra.done.md` with branch, terraform plan summary, and files changed.
