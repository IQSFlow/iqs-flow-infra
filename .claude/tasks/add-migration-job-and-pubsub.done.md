# Task Complete: Add Migration Job + New Pub/Sub Topics

## Changes Made

### 1. Cloud Run Migration Job (`cloud-run.tf`)
Added `google_cloud_run_v2_job.migrations` resource for `run-migrations` job.
- Adapted from task spec: replaced VPC connector (doesn't exist) with Cloud SQL volume mount to match the API service's connectivity pattern.
- Uses `iqs-api` service account, `iqs-flow-db-url` secret, 120s timeout, 0 retries.
- `lifecycle.ignore_changes` on image tag (managed by Cloud Build).

### 2. Pub/Sub Topics (`pubsub.tf`)
Added two new topics:
- `google_pubsub_topic.ticket_created` → `ticket-created`
- `google_pubsub_topic.alert_triggered` → `alert-triggered`

### 3. IAM Roles (`iam.tf`)
Added two new roles for the API service account:
- `roles/aiplatform.user` (Vertex AI)
- `roles/cloudtranslate.user` (Translation)

## Verification

- `terraform validate` — **Success**
- `terraform plan` — **5 to add, 3 to change, 0 to destroy**

### New resources (5 to add):
1. `google_cloud_run_v2_job.migrations`
2. `google_pubsub_topic.ticket_created`
3. `google_pubsub_topic.alert_triggered`
4. `google_project_iam_member.api_vertex`
5. `google_project_iam_member.api_translate`

### Existing drift (3 to change, NOT caused by this task):
- `google_cloud_run_v2_service.api` — env var ordering drift, `client`/`client_version` clearing
- `google_cloud_run_v2_service.web` — env var drift (extra SESSION_SECRET, API_URL in GCP not in TF), min_instance_count 0→1
- `google_cloud_run_v2_service.marketing` — image tag drift, NODE_ENV env added in GCP not in TF

**Note:** The web service drift should be addressed separately — Terraform config is missing `SESSION_SECRET`, `API_URL` env vars and has `min_instance_count = 1` while GCP has `0`.

## Did NOT apply — as instructed.
