output "api_url" {
  value       = google_cloud_run_v2_service.api.uri
  description = "Cloud Run API URL"
}

output "web_url" {
  value       = google_cloud_run_v2_service.web.uri
  description = "Cloud Run Web URL"
}

output "db_connection_name" {
  value       = google_sql_database_instance.main.connection_name
  description = "Cloud SQL connection name for proxy"
}

output "api_service_account" {
  value = google_service_account.api.email
}

output "web_service_account" {
  value = google_service_account.web.email
}
