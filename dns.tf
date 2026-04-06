# Domain mappings are managed outside Terraform (created via gcloud).
# They cause replace-on-apply due to v1/v2 API mismatch.
#
# Existing mappings:
#   iqsflow.com       -> iqs-flow-marketing  (marketing site)
#   app.iqsflow.com   -> iqs-flow-web        (authenticated portal)
#   api.iqsflow.com   -> iqs-flow-api
#
# Domain mapping commands (run manually after terraform apply):
#   gcloud beta run domain-mappings delete --service=iqs-flow-web --domain=iqsflow.com --region=us-central1
#   gcloud beta run domain-mappings create --service=iqs-flow-marketing --domain=iqsflow.com --region=us-central1
#   gcloud beta run domain-mappings create --service=iqs-flow-web --domain=app.iqsflow.com --region=us-central1
