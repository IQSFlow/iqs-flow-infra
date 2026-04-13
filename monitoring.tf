resource "google_monitoring_notification_channel" "email" {
  display_name = "IQS Flow Admin Email"
  type         = "email"

  labels = {
    email_address = "jhinton@iqsflow.com"
  }
}

resource "google_monitoring_alert_policy" "api_errors" {
  display_name = "IQS Flow API - High Error Rate (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run API 5xx errors > 5 in 5 min"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${google_cloud_run_v2_service.api.name}\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "db_connections" {
  display_name = "IQS Flow DB - High Connection Count (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL connections > 80"

    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.project_id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/postgresql/num_backends\""
      comparison      = "COMPARISON_GT"
      threshold_value = 80
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}

# --- Uptime Checks ---

resource "google_monitoring_uptime_check_config" "api_health" {
  display_name = "IQS Flow API - Health Check (${local.env_label})"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/api/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.api_domain
    }
  }
}

resource "google_monitoring_uptime_check_config" "web_health" {
  display_name = "IQS Flow Web - Health Check (${local.env_label})"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.web_domain
    }
  }
}

# --- Alert: API Downtime ---

resource "google_monitoring_alert_policy" "api_downtime" {
  display_name = "IQS Flow API - Downtime (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "API uptime check failing"

    condition_threshold {
      filter          = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.labels.host = \"${var.api_domain}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "120s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }
}

# --- Alert: High Error Rate (additional policy matching task requirements) ---

resource "google_monitoring_alert_policy" "api_high_error_rate" {
  display_name = "IQS Flow API - Critical Error Rate (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run API 5xx error rate > 10% over 10 min"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${google_cloud_run_v2_service.api.name}\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      duration        = "600s"

      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "3600s"
  }
}
