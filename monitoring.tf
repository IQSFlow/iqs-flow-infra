resource "google_monitoring_alert_policy" "api_errors" {
  display_name = "IQS Flow API - High Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run API 5xx errors > 5 in 5 min"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"iqs-flow-api\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "db_connections" {
  display_name = "IQS Flow DB - High Connection Count"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL connections > 80"

    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.project_id}:iqs-flow-db\" AND metric.type = \"cloudsql.googleapis.com/database/postgresql/num_backends\""
      comparison      = "COMPARISON_GT"
      threshold_value = 80
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []
}
