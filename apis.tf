locals {
  enabled_apis = [
    # Core (already enabled)
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicemanagement.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "developerconnect.googleapis.com",

    # New APIs
    "cloudscheduler.googleapis.com",
    "cloudtasks.googleapis.com",
    "gmail.googleapis.com",
    "maps-backend.googleapis.com",
    "clouderrorreporting.googleapis.com",

    # Infra hardening APIs
    "redis.googleapis.com",
    "vpcaccess.googleapis.com",
    "pubsub.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.enabled_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
