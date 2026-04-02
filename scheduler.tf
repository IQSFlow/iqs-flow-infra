resource "google_cloud_scheduler_job" "session_cleanup" {
  name        = "iqs-cleanup-expired-sessions"
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
  name        = "iqs-weekly-report"
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
