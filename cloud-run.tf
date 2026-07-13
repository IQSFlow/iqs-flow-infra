resource "google_cloud_run_v2_service" "api" {
  name     = "iqs-flow-api${local.env_suffix}"
  location = var.region

  # DEFAULT "INGRESS_TRAFFIC_ALL" preserves current internet-facing behavior.
  # Flip var.api_ingress to INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER once
  # api.iqsflow.com sits behind an external HTTPS LB (with Cloud Armor / IAP);
  # see variables.tf and the cutover notes in .done.md.
  ingress = var.api_ingress

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
        name  = "APP_ENV"
        value = local.env_label
      }

      env {
        name  = "CORS_ORIGINS"
        value = local.is_prod ? "https://app.iqsflow.com,https://iqsflow.com,https://www.iqsflow.com" : "https://dev.app.iqsflow.com,https://dev.api.iqsflow.com,http://localhost:3000"
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
    # Cloud Build owns the API's runtime env + secrets at deploy time via
    # `gcloud run deploy --set-env-vars/--update-secrets` (iqs-flow-api/cloudbuild.yaml).
    # That injects secrets NOT declared above — GMAIL_SENDER_SA_EMAIL + IMPERSONATE_USER
    # (Gmail DWD sender), GOOGLE_MAPS_API_KEY, and GEMINI_API_KEY — and also overrides
    # CORS_ORIGINS. If Terraform reconciled the env list, a plain `terraform apply`
    # would STRIP those cloudbuild-injected vars and break email/maps/AI. So ignore
    # env for the same reason `image` is ignored: the deploy pipeline, not Terraform,
    # is the source of truth for what the running revision carries. The env blocks
    # above remain as the create-time baseline + documentation only.
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
    ]
  }
}

resource "google_cloud_run_v2_service" "web" {
  name     = "iqs-flow-web${local.env_suffix}"
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

      env {
        name  = "NEXT_PUBLIC_ENV"
        value = local.env_label
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
    # Cloud Build owns the web app's runtime env + secrets at deploy time via
    # `gcloud run deploy --set-env-vars/--update-secrets` (iqs-flow-web/cloudbuild.yaml).
    # That injects SESSION_SECRET + API_URL (both critical: auth + API base) which
    # are NOT declared above, so if Terraform reconciled the env list a plain
    # `terraform apply` would STRIP them and take the site down. Ignore env for the
    # same reason `image` is ignored: the deploy pipeline, not Terraform, is the
    # source of truth for the running revision's env.
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
    ]
  }
}

# Marketing website (iqsflow.com)
resource "google_cloud_run_v2_service" "marketing" {
  name     = "iqs-flow-marketing${local.env_suffix}"
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
  name     = "run-migrations${local.env_suffix}"
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

# Public invoke for the API. DEFAULT (var.api_allow_public_invoke = true)
# preserves current behavior: anyone can hit the service, so cron/report/cleanup
# routes are reachable at the edge and are guarded ONLY by the in-app OIDC check
# in iqs-flow-api/src/routes/cron.ts (verifyCronAuth -> verifyIdToken, allowing
# the iqs-scheduler@ and iqs-api@ SAs). Setting this false requires fronting the
# API with an IAP/LB identity and granting run.invoker to that identity AND to
# google_service_account.scheduler, or all callers (dashboard + cron) get 403.
resource "google_cloud_run_v2_service_iam_member" "api_public" {
  count = var.api_allow_public_invoke ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# When the API is no longer allUsers-invokable, the scheduler SA still needs an
# explicit run.invoker grant so cron jobs (scheduler.tf) keep working. Inert
# while public invoke is on (the allUsers grant already covers the scheduler).
resource "google_cloud_run_v2_service_iam_member" "api_scheduler_invoke" {
  count = var.api_allow_public_invoke ? 0 : 1

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}
