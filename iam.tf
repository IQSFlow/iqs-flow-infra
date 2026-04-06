# --- Service Accounts ---

resource "google_service_account" "api" {
  account_id   = "iqs-api"
  display_name = "IQS Flow API"
  description  = "Service account for Cloud Run API service"
}

resource "google_service_account" "web" {
  account_id   = "iqs-web"
  display_name = "IQS Flow Web"
  description  = "Service account for Cloud Run Web service"
}

resource "google_service_account" "build" {
  account_id   = "iqs-build"
  display_name = "IQS Flow Cloud Build"
  description  = "Service account for Cloud Build pipelines"
}

resource "google_service_account" "scheduler" {
  account_id   = "iqs-scheduler"
  display_name = "IQS Flow Scheduler"
  description  = "Service account for Cloud Scheduler jobs"
}

# --- API SA Roles ---

resource "google_project_iam_member" "api_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "api_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# --- Web SA Roles ---

resource "google_project_iam_member" "web_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.web.email}"
}

# --- Build SA Roles ---

resource "google_project_iam_member" "build_ar" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.build.email}"
}

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

resource "google_cloud_run_v2_service_iam_member" "build_deploy_marketing" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.marketing.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.build.email}"
}

resource "google_project_iam_member" "build_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.build.email}"
}

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

resource "google_project_iam_member" "build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.build.email}"
}

# --- Scheduler SA Roles ---

resource "google_project_iam_member" "scheduler_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}
