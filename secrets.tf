resource "google_secret_manager_secret" "db_url" {
  secret_id = "iqs-flow-db-url${local.env_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "session_secret" {
  secret_id = "iqs-flow-session-secret${local.env_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "api_url" {
  secret_id = "iqs-flow-api-url${local.env_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "smtp_pass" {
  secret_id = "iqs-flow-smtp-pass${local.env_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "google_maps_key" {
  secret_id = "google-maps-api-key${local.env_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "aerodatabox_key" {
  secret_id = "aerodatabox-api-key${local.env_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "smtp_user" {
  secret_id = "iqs-flow-smtp-user${local.env_suffix}"
  replication {
    auto {}
  }
}

# Secret values are managed via gcloud CLI (not stored in Terraform state)
# Use: echo -n "value" | gcloud secrets versions add SECRET_NAME --data-file=-
