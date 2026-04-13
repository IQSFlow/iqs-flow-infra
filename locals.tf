locals {
  # "default" workspace = dev (no suffix, preserves existing resource names)
  # "prod" workspace = production (gets "-prod" suffix on all resources)
  is_prod    = terraform.workspace == "prod"
  env_suffix = local.is_prod ? "-prod" : ""
  env_label  = local.is_prod ? "prod" : "dev"
}
