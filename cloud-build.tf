resource "google_cloudbuild_trigger" "api_deploy" {
  name            = "iqs-flow-api-deploy"
  location        = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.build.email}"

  repository_event_config {
    repository = "projects/${var.project_id}/locations/${var.region}/connections/iqs-flow-org/repositories/iqs-flow-api"
    push {
      tag = "^v.*$"
    }
  }

  filename = "cloudbuild.yaml"
}

resource "google_cloudbuild_trigger" "web_deploy" {
  name            = "iqs-flow-web-deploy"
  location        = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.build.email}"

  repository_event_config {
    repository = "projects/${var.project_id}/locations/${var.region}/connections/iqs-flow-org/repositories/iqs-flow-web"
    push {
      tag = "^v.*$"
    }
  }

  filename = "cloudbuild.yaml"
}

resource "google_cloudbuild_trigger" "shared_publish" {
  name            = "iqs-flow-shared-publish"
  location        = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.build.email}"

  repository_event_config {
    repository = "projects/${var.project_id}/locations/${var.region}/connections/iqs-flow-org/repositories/iqs-flow-shared"
    push {
      tag = "^v.*$"
    }
  }

  filename = "cloudbuild.yaml"
}
