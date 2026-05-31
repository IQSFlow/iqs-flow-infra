# --- Cloud Scheduler jobs ---
#
# All jobs target current /api/cron/* routes in iqs-flow-api/src/routes/cron.ts
# and authenticate with the iqs-scheduler@ service account via OIDC. The API's
# verifyCronAuth() validates the OIDC token and allows the iqs-scheduler@ (and
# legacy iqs-api@) SAs. Previously two jobs pointed at retired routes
# (/api/health/cleanup, /api/reports/weekly) and daily_cleanup ran as the API SA
# instead of the scheduler SA — both fixed here.
#
# OIDC audience: Cloud Scheduler defaults the token audience to the target URI.
# That works while the service is allUsers-invokable. If var.api_allow_public_invoke
# is flipped to false (LB/IAP fronting), set oidc_token.audience to the canonical
# Cloud Run URL and grant the scheduler SA run.invoker (see cloud-run.tf
# api_scheduler_invoke).

locals {
  # Canonical base URL for cron targets. Uses the Cloud Run service URI so jobs
  # keep working before/independent of any custom-domain or LB cutover.
  cron_base_uri = google_cloud_run_v2_service.api.uri
}

# Nightly housekeeping: expired sessions, stale location events, old queue
# items, expired reset tokens. Replaces the old session_cleanup +
# daily_cleanup pair that both targeted cleanup (one via the retired
# /api/health/cleanup route, one running as the wrong SA).
resource "google_cloud_scheduler_job" "daily_cleanup" {
  name             = "iqs-flow-daily-cleanup${local.env_suffix}"
  description      = "Daily cleanup of expired sessions, old location events, queue items, and reset tokens"
  schedule         = "0 3 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/cleanup"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Weekly inspection/activity digest emails, Mondays 08:00 ET.
# Replaces weekly_report -> retired /api/reports/weekly route.
resource "google_cloud_scheduler_job" "weekly_digest" {
  name             = "iqs-flow-weekly-digest${local.env_suffix}"
  description      = "Send weekly summary digest emails (Mondays)"
  schedule         = "0 8 * * 1"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/weekly-digest"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Daily activity digest emails, 07:00 ET.
resource "google_cloud_scheduler_job" "daily_digest" {
  name             = "iqs-flow-daily-digest${local.env_suffix}"
  description      = "Send daily summary digest emails"
  schedule         = "0 7 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/daily-digest"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Generate per-tenant daily tasks at midnight ET.
resource "google_cloud_scheduler_job" "generate_daily_tasks" {
  name             = "iqs-flow-generate-daily-tasks${local.env_suffix}"
  description      = "Generate daily tasks for all tenants (midnight)"
  schedule         = "0 0 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/generate-daily-tasks"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Materialize scheduled tickets into live tickets, every 15 minutes.
resource "google_cloud_scheduler_job" "process_scheduled_tickets" {
  name             = "iqs-flow-process-scheduled-tickets${local.env_suffix}"
  description      = "Process scheduled tickets into live tickets (every 15 min)"
  schedule         = "*/15 * * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/process-scheduled-tickets"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Compute gate-turn metrics for airport sites, every 15 minutes.
resource "google_cloud_scheduler_job" "gate_turns" {
  name             = "iqs-flow-gate-turns${local.env_suffix}"
  description      = "Compute gate-turn metrics for airport sites (every 15 min)"
  schedule         = "*/15 * * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/gate-turns"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Sync today's flights for airports with linked sites, hourly.
resource "google_cloud_scheduler_job" "sync_flights" {
  name             = "iqs-flow-sync-flights${local.env_suffix}"
  description      = "Sync today's flights for airports with linked sites (hourly)"
  schedule         = "0 * * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/sync-flights"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Generate work orders from preventive-maintenance plans, daily 02:00 ET.
resource "google_cloud_scheduler_job" "process_pm_plans" {
  name             = "iqs-flow-process-pm-plans${local.env_suffix}"
  description      = "Process preventive-maintenance plans into work orders (daily)"
  schedule         = "0 2 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/process-pm-plans"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Recompute value-added-service (VAS) metrics, daily 04:00 ET.
resource "google_cloud_scheduler_job" "compute_vas" {
  name             = "iqs-flow-compute-vas${local.env_suffix}"
  description      = "Recompute value-added-service metrics (daily)"
  schedule         = "0 4 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${local.cron_base_uri}/api/cron/compute-vas"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }
}
