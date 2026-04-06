# Wave 4: Marketing Infra — Done

**Branch:** `claude/marketing-infra`
**Commit:** `07b8850`

## Terraform Plan Summary

Plan: 3 to add, 0 to change, 0 to destroy.

- `google_cloud_run_v2_service.marketing` — new Cloud Run service (port 3000, min 0 / max 2)
- `google_cloud_run_v2_service_iam_member.marketing_public` — public access
- `google_cloud_run_v2_service_iam_member.build_deploy_marketing` — scoped build SA deploy permission

## Files Changed

- `cloud-run.tf` — added marketing service + public IAM binding
- `iam.tf` — added build_deploy_marketing scoped IAM binding
- `dns.tf` — updated domain mapping comments for web repo split

## Post-apply (manual)

1. `terraform apply`
2. Remap domains via gcloud:
   - `gcloud beta run domain-mappings delete --service=iqs-flow-web --domain=iqsflow.com --region=us-central1`
   - `gcloud beta run domain-mappings create --service=iqs-flow-marketing --domain=iqsflow.com --region=us-central1`
   - `gcloud beta run domain-mappings create --service=iqs-flow-web --domain=app.iqsflow.com --region=us-central1`
