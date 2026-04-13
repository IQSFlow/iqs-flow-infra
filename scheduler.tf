resource "google_cloud_scheduler_job" "session_cleanup" {
  name        = "iqs-cleanup-expired-sessions${local.env_suffix}"
  description = "Clean up expired sessions nightly"
  schedule    = "0 3 * * *"
  time_zone   = "America/New_York"

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.api.uri}/api/health/cleanup"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }
}

resource "google_cloud_scheduler_job" "weekly_report" {
  name        = "iqs-weekly-report${local.env_suffix}"
  description = "Generate weekly inspection summary"
  schedule    = "0 8 * * 1"
  time_zone   = "America/New_York"

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.api.uri}/api/reports/weekly"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }
}

resource "google_cloud_scheduler_job" "daily_cleanup" {
  name             = "iqs-flow-daily-cleanup${local.env_suffix}"
  description      = "Runs daily cleanup of old location events, audit logs, sessions, and notifications"
  schedule         = "0 3 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "300s"

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.api.uri}/api/cron/cleanup"
    oidc_token {
      service_account_email = google_service_account.api.email
    }
  }

  retry_config {
    retry_count = 3
  }
}
