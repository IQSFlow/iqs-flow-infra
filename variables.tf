variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "crested-booking-488922-f7"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "db_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-1-3840"
}

variable "db_password" {
  description = "Cloud SQL iqsflow user password"
  type        = string
  sensitive   = true
}

variable "session_secret" {
  description = "Session signing secret"
  type        = string
  sensitive   = true
}

variable "smtp_pass" {
  description = "Gmail app password for noreply@iqsflow.com"
  type        = string
  sensitive   = true
}

variable "api_domain" {
  description = "Custom domain for API"
  type        = string
  default     = "api.iqsflow.com"
}

variable "web_domain" {
  description = "Custom domain for Web"
  type        = string
  default     = "iqsflow.com"
}
