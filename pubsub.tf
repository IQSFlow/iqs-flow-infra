# --- Pub/Sub Topics ---

resource "google_pubsub_topic" "worker_location" {
  name = "worker-location${local.env_suffix}"
}

resource "google_pubsub_topic" "task_assignment" {
  name = "task-assignment${local.env_suffix}"
}

resource "google_pubsub_topic" "inspection_complete" {
  name = "inspection-complete${local.env_suffix}"
}

resource "google_pubsub_topic" "work_order_updated" {
  name = "work-order-updated${local.env_suffix}"
}

resource "google_pubsub_topic" "ticket_created" {
  name = "ticket-created${local.env_suffix}"
}

resource "google_pubsub_topic" "alert_triggered" {
  name = "alert-triggered${local.env_suffix}"
}

resource "google_pubsub_topic" "dead_letter" {
  name = "dead-letter${local.env_suffix}"
}

# --- Subscriptions ---

resource "google_pubsub_subscription" "api_worker_location" {
  name  = "api-worker-location${local.env_suffix}"
  topic = google_pubsub_topic.worker_location.id

  ack_deadline_seconds = 30

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
}

# --- IAM: API SA can publish and consume Pub/Sub ---

resource "google_project_iam_member" "api_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "api_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.api.email}"
}
