resource "google_monitoring_notification_channel" "email" {
  display_name = "IQS Flow Admin Email"
  type         = "email"

  labels = {
    email_address = "jhinton@iqsflow.com"
  }
}

resource "google_monitoring_alert_policy" "api_errors" {
  # Absolute-count alert: trips on any meaningful burst of 5xx, even at low
  # traffic where a ratio alert would stay quiet. Paired with api_5xx_ratio
  # below (which catches sustained elevated error *rate* at higher traffic).
  # Renamed from the misleading "High Error Rate" — this is a count, not a rate.
  display_name = "IQS Flow API - 5xx Error Count (${local.env_label})"
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

# --- Alert: genuine 5xx error RATE (ratio of 5xx to total requests) ---
# Replaces the old "Critical Error Rate" policy, which was mislabeled: it used
# ALIGN_SUM on the 5xx count (threshold 10) and therefore overlapped with
# api_errors (count > 5) instead of measuring a rate. This version uses MQL to
# divide 5xx request_count by total request_count and alerts on a true ratio,
# so it stays meaningful regardless of traffic volume.
resource "google_monitoring_alert_policy" "api_5xx_ratio" {
  display_name = "IQS Flow API - 5xx Error Rate > 10% (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run API 5xx ratio > 10% over 10 min"

    condition_monitoring_query_language {
      query    = <<-EOT
        fetch cloud_run_revision
        | metric 'run.googleapis.com/request_count'
        | filter resource.service_name == '${google_cloud_run_v2_service.api.name}'
        | align rate(10m)
        | { t_5xx: filter metric.response_code_class == '5xx' | group_by [], [v: sum(value.request_count)]
          ; t_all: group_by [], [v: sum(value.request_count)] }
        | join
        | value [ratio: t_5xx.v / t_all.v]
        | condition ratio > 0.10
      EOT
      duration = "600s"

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "3600s"
  }
}

# --- Alert: Cloud SQL CPU utilization ---
resource "google_monitoring_alert_policy" "db_cpu" {
  display_name = "IQS Flow DB - High CPU (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL CPU utilization > 80% for 5 min"

    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.project_id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }
}

# --- Alert: Cloud SQL disk utilization (running out of storage) ---
resource "google_monitoring_alert_policy" "db_disk" {
  display_name = "IQS Flow DB - High Disk Utilization (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL disk utilization > 85% for 5 min"

    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.project_id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/disk/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.85
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }
}

# --- Alert: Pub/Sub dead-letter queue accumulation ---
# Any message landing in the dead-letter topic means a subscriber exhausted its
# delivery attempts (see pubsub.tf dead_letter_policy, max_delivery_attempts=5).
# Alerts as soon as unacked messages appear so failures aren't silently dropped.
resource "google_monitoring_alert_policy" "pubsub_dead_letter" {
  display_name = "IQS Flow Pub/Sub - Dead-Letter Messages (${local.env_label})"
  combiner     = "OR"

  conditions {
    display_name = "Dead-letter topic received messages > 0 in 5 min"

    condition_threshold {
      filter          = "resource.type = \"pubsub_topic\" AND resource.labels.topic_id = \"${google_pubsub_topic.dead_letter.name}\" AND metric.type = \"pubsub.googleapis.com/topic/send_message_operation_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
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
