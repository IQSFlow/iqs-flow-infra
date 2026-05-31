resource "google_storage_bucket" "uploads" {
  name          = "${var.project_id}-iqs-flow-uploads${local.env_suffix}"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  # Tightened from a wildcard "https://iqs-flow-web-*-uc.a.run.app" origin
  # (GCS CORS does not honor wildcards anyway, so it was effectively dead) to the
  # explicit app domains per environment. Mirrors the API CORS_ORIGINS allowlist
  # in cloud-run.tf. localhost is dev-only for local upload testing.
  cors {
    origin = local.is_prod ? [
      "https://app.iqsflow.com",
      "https://iqsflow.com",
      "https://www.iqsflow.com",
      ] : [
      "https://dev.app.iqsflow.com",
      "http://localhost:3000",
    ]
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

resource "google_storage_bucket_iam_member" "api_upload" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.api.email}"
}
