# VPC network required for Redis (Memorystore) — Cloud SQL will continue to use
# public IP as before; the VPC is only required here for Redis connectivity.
resource "google_compute_network" "vpc" {
  name                    = "iqs-flow-vpc"
  auto_create_subnetworks = true
}

resource "google_vpc_access_connector" "connector" {
  name          = "iqs-flow-connector"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.8.0.0/28"

  depends_on = [google_project_service.enabled]
}

resource "google_redis_instance" "cache" {
  name               = "iqs-flow-cache"
  tier               = "BASIC"
  memory_size_gb     = 1
  region             = var.region
  authorized_network = google_compute_network.vpc.self_link
  redis_version      = "REDIS_7_0"
  display_name       = "IQS Flow Cache"

  labels = {
    environment = "production"
    service     = "iqs-flow"
  }

  depends_on = [google_project_service.enabled]
}

output "redis_host" {
  value = google_redis_instance.cache.host
}

output "redis_port" {
  value = google_redis_instance.cache.port
}
