# Domain Mappings (managed via gcloud, not Terraform)
# They cause replace-on-apply due to v1/v2 API mismatch.
#
# Production (workspace: prod):
#   iqsflow.com          -> iqs-flow-marketing-prod
#   app.iqsflow.com      -> iqs-flow-web-prod
#   api.iqsflow.com      -> iqs-flow-api-prod
#
# Development (workspace: default):
#   dev.iqsflow.com      -> iqs-flow-marketing  (no suffix, original names)
#   dev.app.iqsflow.com  -> iqs-flow-web        (no suffix, original names)
#   dev.api.iqsflow.com  -> iqs-flow-api        (no suffix, original names)
#
# Example commands:
#   gcloud beta run domain-mappings create --service=iqs-flow-web-prod --domain=app.iqsflow.com --region=us-central1
#   gcloud beta run domain-mappings create --service=iqs-flow-api-prod --domain=api.iqsflow.com --region=us-central1
#   gcloud beta run domain-mappings create --service=iqs-flow-marketing-prod --domain=iqsflow.com --region=us-central1
