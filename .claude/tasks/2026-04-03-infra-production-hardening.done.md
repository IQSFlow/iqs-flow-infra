# Infra Production Hardening

> **Priority:** P1 - after secrets task completes
> **Branch:** `claude/v5-infra-hardening`
> **Isolation:** Use a git worktree (`isolation: "worktree"`) for this work so other agents aren't blocked.

## Required Skills
- `superpowers:verification-before-completion` - before claiming done
- `commit-commands:commit` - for each change

## Context
Engineering audit found: no read replica, no caching layer, no Pub/Sub, no uptime monitoring alerts. This task adds production hardening infrastructure via Terraform.

**DO NOT run `terraform apply` - the user will review and apply manually. Only write the .tf files.**

## Task 1: Add Cloud SQL read replica

**File:** `cloud-sql.tf`

Add a read replica of the main Cloud SQL instance:

```hcl
resource "google_sql_database_instance" "read_replica" {
  name                 = "iqs-flow-db-replica"
  master_instance_name = google_sql_database_instance.main.name
  region               = var.region
  database_version     = google_sql_database_instance.main.database_version

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = "db-f1-micro"  # Start small, scale up if needed
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled = false
      private_network = google_compute_network.vpc.self_link  # Adjust if VPC reference differs
    }
  }

  deletion_protection = false
}
```

Also add a secret for the read replica connection string:
```hcl
resource "google_secret_manager_secret" "db_read_url" {
  secret_id = "iqs-flow-db-read-url"
  replication {
    auto {}
  }
}
```

And wire it to the API Cloud Run service as an env var:
```hcl
env {
  name = "DATABASE_READ_URL"
  value_source {
    secret_key_ref {
      secret  = google_secret_manager_secret.db_read_url.secret_id
      version = "latest"
    }
  }
}
```

**NOTE:** Check the existing `cloud-sql.tf` for the actual VPC/network reference before using `google_compute_network.vpc.self_link`. Adjust to match the existing configuration.

## Task 2: Add Redis (Memorystore) for caching

**Create `redis.tf`:**

```hcl
resource "google_redis_instance" "cache" {
  name           = "iqs-flow-cache"
  tier           = "BASIC"  # Start with basic, upgrade to STANDARD_HA for production
  memory_size_gb = 1
  region         = var.region

  authorized_network = google_compute_network.vpc.self_link  # Adjust to match existing VPC

  redis_version = "REDIS_7_0"

  display_name = "IQS Flow Cache"

  labels = {
    environment = "production"
    service     = "iqs-flow"
  }
}

output "redis_host" {
  value = google_redis_instance.cache.host
}

output "redis_port" {
  value = google_redis_instance.cache.port
}
```

Wire Redis host/port to the API Cloud Run service:
```hcl
env {
  name  = "REDIS_HOST"
  value = google_redis_instance.cache.host
}

env {
  name  = "REDIS_PORT"
  value = tostring(google_redis_instance.cache.port)
}
```

**NOTE:** Check if a VPC connector exists for Cloud Run to reach Memorystore. If not, add:
```hcl
resource "google_vpc_access_connector" "connector" {
  name          = "iqs-flow-connector"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.8.0.0/28"
}
```

And reference it in the Cloud Run service template:
```hcl
template {
  vpc_access {
    connector = google_vpc_access_connector.connector.id
    egress    = "PRIVATE_RANGES_ONLY"
  }
}
```

## Task 3: Add Cloud Pub/Sub topics

**Create `pubsub.tf`:**

```hcl
# Topics for domain events
resource "google_pubsub_topic" "worker_location" {
  name = "worker-location"
  labels = {
    service = "iqs-flow"
  }
}

resource "google_pubsub_topic" "task_assignment" {
  name = "task-assignment"
  labels = {
    service = "iqs-flow"
  }
}

resource "google_pubsub_topic" "inspection_complete" {
  name = "inspection-complete"
  labels = {
    service = "iqs-flow"
  }
}

resource "google_pubsub_topic" "work_order_updated" {
  name = "work-order-updated"
  labels = {
    service = "iqs-flow"
  }
}

# Dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "dead-letter"
  labels = {
    service = "iqs-flow"
  }
}

# Subscriptions for API service
resource "google_pubsub_subscription" "api_worker_location" {
  name  = "api-worker-location"
  topic = google_pubsub_topic.worker_location.name

  ack_deadline_seconds = 20

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# Grant API service account publish/subscribe access
resource "google_pubsub_topic_iam_member" "api_publish" {
  for_each = toset([
    google_pubsub_topic.worker_location.name,
    google_pubsub_topic.task_assignment.name,
    google_pubsub_topic.inspection_complete.name,
    google_pubsub_topic.work_order_updated.name,
  ])

  topic  = each.value
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.api.email}"
}

resource "google_pubsub_subscription_iam_member" "api_subscribe" {
  subscription = google_pubsub_subscription.api_worker_location.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.api.email}"
}
```

## Task 4: Add uptime monitoring and alerting

**File:** `monitoring.tf` (add to existing or create)

```hcl
# Uptime check for API health endpoint
resource "google_monitoring_uptime_check_config" "api_health" {
  display_name = "IQS Flow API Health"
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
      host       = "api.iqsflow.com"
    }
  }
}

# Uptime check for Web
resource "google_monitoring_uptime_check_config" "web_health" {
  display_name = "IQS Flow Web"
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
      host       = "iqsflow.com"
    }
  }
}

# Alert policy for API downtime
resource "google_monitoring_alert_policy" "api_downtime" {
  display_name = "IQS Flow API Down"
  combiner     = "OR"

  conditions {
    display_name = "API health check failing"

    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.api_health.uptime_check_id}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }
    }
  }

  notification_channels = []  # Add notification channel IDs when email/Slack alerting is configured

  alert_strategy {
    auto_close = "1800s"
  }
}

# Alert for high error rate on API Cloud Run
resource "google_monitoring_alert_policy" "api_error_rate" {
  display_name = "IQS Flow API High Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Error rate > 5%"

    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"iqs-flow-api\" AND metric.label.response_code_class!=\"2xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = []
}
```

## Task 5: Add Cloud Scheduler for daily cleanup

**File:** `scheduler.tf` (add to existing)

```hcl
resource "google_cloud_scheduler_job" "daily_cleanup" {
  name             = "iqs-flow-daily-cleanup"
  description      = "Runs daily cleanup of old location events, audit logs, sessions, and notifications"
  schedule         = "0 3 * * *"  # 3 AM UTC daily
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
```

## After All Changes

```bash
terraform fmt       # format all .tf files
terraform validate  # must pass
```

**DO NOT run `terraform apply`.**

List the resources that will be created when the user applies:
- Cloud SQL read replica
- Memorystore Redis instance (1GB)
- VPC connector (if needed)
- 4 Pub/Sub topics + 1 dead letter topic + subscriptions
- 2 uptime checks (API + Web)
- 2 alert policies (downtime + error rate)
- 1 Cloud Scheduler job (daily cleanup)
- New secrets and env vars on API Cloud Run

## Definition of Done
- cloud-sql.tf has read replica resource
- redis.tf has Memorystore instance + VPC connector if needed
- pubsub.tf has 5 topics, subscriptions, IAM bindings
- monitoring.tf has uptime checks and alert policies
- scheduler.tf has daily cleanup job
- All env vars wired to API Cloud Run service
- `terraform fmt` and `terraform validate` pass
- Committed and pushed
