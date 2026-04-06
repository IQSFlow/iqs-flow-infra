resource "google_cloud_run_v2_service" "api" {
  name     = "iqs-flow-api"
  location = var.region

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = 1
      max_instance_count = 3
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      # Image tag is managed by Cloud Build triggers, not Terraform.
      # lifecycle.ignore_changes prevents Terraform from reverting deployments.
      image = "${var.region}-docker.pkg.dev/${var.project_id}/iqs-flow/iqs-flow-api:latest"

      ports {
        container_port = 4000
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name = "SMTP_USER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.smtp_user.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "SESSION_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.session_secret.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "SMTP_PASS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.smtp_pass.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "AERODATABOX_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.aerodatabox_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.uploads.name
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      startup_probe {
        http_get {
          path = "/api/health"
          port = 4000
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 3
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}

resource "google_cloud_run_v2_service" "web" {
  name     = "iqs-flow-web"
  location = var.region

  template {
    service_account = google_service_account.web.email

    scaling {
      min_instance_count = 1
      max_instance_count = 3
    }

    containers {
      # Image tag is managed by Cloud Build triggers, not Terraform.
      # lifecycle.ignore_changes prevents Terraform from reverting deployments.
      image = "${var.region}-docker.pkg.dev/${var.project_id}/iqs-flow/iqs-flow-web:latest"

      ports {
        container_port = 3000
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      startup_probe {
        http_get {
          path = "/"
          port = 3000
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 3
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}

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

# --- Migration Job ---

resource "google_cloud_run_v2_job" "migrations" {
  name     = "run-migrations"
  location = var.region

  template {
    template {
      service_account = google_service_account.api.email
      timeout         = "120s"
      max_retries     = 0

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [google_sql_database_instance.main.connection_name]
        }
      }

      containers {
        image   = "${var.region}-docker.pkg.dev/${var.project_id}/iqs-flow/iqs-flow-api:latest"
        command = ["npx"]
        args    = ["prisma", "migrate", "deploy"]

        env {
          name = "DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_url.secret_id
              version = "latest"
            }
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }
}

# Public access
resource "google_cloud_run_v2_service_iam_member" "web_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "api_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
