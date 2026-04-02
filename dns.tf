# Domain mappings are managed outside Terraform (created via gcloud).
# They cause replace-on-apply due to v1/v2 API mismatch.
#
# Existing mappings:
#   iqsflow.com     → iqs-flow-web
#   api.iqsflow.com → iqs-flow-api
#
# To create/modify:
#   gcloud beta run domain-mappings create --service=SERVICE --domain=DOMAIN --region=us-central1
