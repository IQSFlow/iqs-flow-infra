resource "google_sql_database_instance" "main" {
  name             = "iqs-flow-db${local.env_suffix}"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    ip_configuration {
      # DEFAULTS PRESERVE CURRENT BEHAVIOR: public IPv4 on, SSL enforced.
      # Hardening path (see variables.tf / .done.md cutover steps):
      #   1. Provision a VPC + Service Networking peering, set db_private_network.
      #   2. Wire a Serverless VPC Access connector into Cloud Run (cloud-run.tf).
      #   3. db_enable_private_ip = true  -> adds Private IP.
      #   4. After every client reaches the DB privately, db_ipv4_enabled = false.
      # Cloud SQL requires at least one connectivity method, so never disable
      # IPv4 before Private IP is live.
      ipv4_enabled    = var.db_ipv4_enabled
      private_network = var.db_enable_private_ip && var.db_private_network != "" ? var.db_private_network : null
      ssl_mode        = "ENCRYPTED_ONLY"

      dynamic "authorized_networks" {
        for_each = var.db_authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
    }
  }

  deletion_protection = true

  # Private IP requires the Service Networking peering to exist first.
  # No-op while db_enable_private_ip = false (the connection isn't created).
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# --- Private IP scaffolding (inert until db_enable_private_ip = true) ---
# When enabled, reserves an internal IP range and establishes the Service
# Networking peering Cloud SQL Private IP requires. count keeps these out of the
# plan entirely while the default (public IPv4) path is in effect, so applying
# this branch as-is is a no-op for connectivity.

resource "google_compute_global_address" "private_ip_range" {
  count = var.db_enable_private_ip && var.db_private_network != "" ? 1 : 0

  name          = "iqs-flow-sql-private-ip${local.env_suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.db_private_network
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count = var.db_enable_private_ip && var.db_private_network != "" ? 1 : 0

  network                 = var.db_private_network
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range[0].name]
}

resource "google_sql_database" "iqsflow" {
  name     = "iqsflow"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "iqsflow" {
  name     = "iqsflow"
  instance = google_sql_database_instance.main.name
  password = var.db_password
}
