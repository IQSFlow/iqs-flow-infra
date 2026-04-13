resource "google_cloud_tasks_queue" "email" {
  name     = "iqs-email-queue${local.env_suffix}"
  location = var.region

  rate_limits {
    max_dispatches_per_second = 5
    max_concurrent_dispatches = 3
  }

  retry_config {
    max_attempts  = 5
    min_backoff   = "10s"
    max_backoff   = "300s"
    max_doublings = 3
  }
}

resource "google_cloud_tasks_queue" "reports" {
  name     = "iqs-reports-queue${local.env_suffix}"
  location = var.region

  rate_limits {
    max_dispatches_per_second = 1
    max_concurrent_dispatches = 1
  }

  retry_config {
    max_attempts = 3
    min_backoff  = "30s"
    max_backoff  = "600s"
  }
}
