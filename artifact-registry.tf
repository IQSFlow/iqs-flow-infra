resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = "iqs-flow"
  format        = "DOCKER"
  description   = "Docker images for IQS Flow services"
}

resource "google_artifact_registry_repository" "npm" {
  location      = var.region
  repository_id = "iqs-flow-npm"
  format        = "NPM"
  description   = "npm packages (@iqsflow/shared)"
}
