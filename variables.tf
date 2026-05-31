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

# NOTE: `session_secret` and `smtp_pass` variables were removed. Their secret
# VALUES are managed via gcloud (see secrets.tf), so Terraform never consumed
# these inputs. The shells `google_secret_manager_secret.session_secret` /
# `.smtp_pass` remain. terraform.tfvars still carries orphaned entries for them;
# remove those two lines from terraform.tfvars (managed outside this repo) to
# clear the resulting "value set for undeclared variable" warning.

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

variable "marketing_domain" {
  description = "Custom domain for marketing site"
  type        = string
  default     = "iqsflow.com"
}

variable "environment" {
  description = "Environment name, derived from workspace. Override via tfvars if needed."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

# --- Cloud SQL network hardening (cloud-sql.tf) ---
# DEFAULTS PRESERVE CURRENT BEHAVIOR. Flipping these without a connectivity
# cutover (Serverless VPC Access connector on Cloud Run + Service Networking
# peering) WILL break the API → DB path. See .claude/tasks/infra-hardening.done.md.

variable "db_enable_private_ip" {
  description = <<-EOT
    Enable Private IP (Service Networking) on Cloud SQL. Requires
    `db_private_network` to be set and Service Networking peering established
    BEFORE enabling, and a Serverless VPC Access connector wired into Cloud Run.
    Defaults to false to preserve the current public-IPv4 connectivity.
  EOT
  type        = bool
  default     = false
}

variable "db_private_network" {
  description = <<-EOT
    Self-link of the VPC network to peer Cloud SQL into when
    `db_enable_private_ip = true` (e.g.
    projects/<project>/global/networks/<network>). Empty disables Private IP
    config regardless of the toggle.
  EOT
  type        = string
  default     = ""
}

variable "db_ipv4_enabled" {
  description = <<-EOT
    Whether the Cloud SQL instance keeps its public IPv4 address.
    DEFAULT true (current behavior). Only set false AFTER Private IP/PSC is live
    and every client (Cloud Run, migration job, admin proxy) reaches the DB
    privately — otherwise connectivity breaks. Cloud SQL requires at least one
    connectivity method, so do not disable IPv4 while `db_enable_private_ip` is
    false.
  EOT
  type        = bool
  default     = true
}

variable "db_authorized_networks" {
  description = <<-EOT
    Optional allowlist of CIDR ranges permitted to reach the public IP while
    IPv4 remains enabled. Empty list = no allowlist change (current behavior).
    Cloud Run egress is dynamic, so this is intended for admin/proxy ranges, not
    the app tier.
  EOT
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# --- Cloud Run ingress hardening (cloud-run.tf) ---
# DEFAULT preserves the current allUsers-invokable, internet-facing API.

variable "api_ingress" {
  description = <<-EOT
    Cloud Run ingress for the API service. DEFAULT "INGRESS_TRAFFIC_ALL"
    preserves current behavior. Set "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" to
    only accept traffic fronted by an external HTTPS LB (with Cloud Armor / IAP)
    once api.iqsflow.com is moved behind that LB. Direct *.run.app and the bare
    custom domain stop working when this is flipped, so cut DNS over first.
  EOT
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"

  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.api_ingress)
    error_message = "api_ingress must be one of INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "api_allow_public_invoke" {
  description = <<-EOT
    Whether the API Cloud Run service grants run.invoker to allUsers. DEFAULT
    true preserves current behavior (cron/report/cleanup routes are then guarded
    only by their in-app OIDC check). Set false ONLY after fronting the service
    with an IAP/LB-backed identity and granting run.invoker to that identity and
    to the scheduler SA, otherwise all callers (including the dashboard) get 403.
  EOT
  type        = bool
  default     = true
}
