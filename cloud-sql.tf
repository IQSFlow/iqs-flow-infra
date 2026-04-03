resource "google_sql_database_instance" "main" {
  name             = "iqs-flow-db"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = false
      start_time                     = "03:00"
    }
  }

  deletion_protection = true
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
