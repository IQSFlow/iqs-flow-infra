# Security Fixes - Infra Repo

Work on branch `claude/security-fixes`. Do NOT run `terraform apply`. Do NOT push.

If something is unclear, make the safe choice and note it in your commit message. Do NOT stop to ask questions.

Reference: `C:/Users/joshu/Flow/iqs-flow-shared/.security-reports/sec-ship-2026-04-05-201929.md`

## Fixes (do all of these, in order)

1. **Disable Cloud SQL public IP.** In `cloud-sql.tf:13`, set `ipv4_enabled = false`. Cloud Run connects via Cloud SQL Auth Proxy so public IP is unnecessary.

2. **Enforce SSL on Cloud SQL.** In `cloud-sql.tf:12-14`, add `ssl_mode = "ENCRYPTED_ONLY"`.

3. **Enable point-in-time recovery.** In `cloud-sql.tf:18`, set `point_in_time_recovery_enabled = true`.

4. **Remove public access from uploads bucket.** In `storage.tf:31-35`, delete the `google_storage_bucket_iam_member` resource that grants `objectViewer` to `allUsers`. The API will serve files via signed URLs (that change will be made in the API repo separately).

5. **Scope build SA IAM roles.** In `iam.tf:69-73`, change `serviceAccountUser` from project-level to specific service account:
   ```hcl
   resource "google_service_account_iam_member" "build_sa_user" {
     service_account_id = google_service_account.api.name
     role               = "roles/iam.serviceAccountUser"
     member             = "serviceAccount:${google_service_account.build.email}"
   }
   ```
   Do the same for the web service account.

6. **Scope run.developer role.** In `iam.tf:57-61`, change from project-level `roles/run.developer` to service-level `roles/run.developer` on specific Cloud Run services:
   ```hcl
   resource "google_cloud_run_v2_service_iam_member" "build_deploy_api" {
     project  = var.project_id
     location = var.region
     name     = google_cloud_run_v2_service.api.name
     role     = "roles/run.developer"
     member   = "serviceAccount:${google_service_account.build.email}"
   }
   ```
   Add one for each Cloud Run service (api, web).

7. **Add notification channel to alerts.** In `monitoring.tf`, create an email notification channel:
   ```hcl
   resource "google_monitoring_notification_channel" "email" {
     display_name = "Admin Email"
     type         = "email"
     labels = {
       email_address = "jhinton@iqsflow.com"
     }
   }
   ```
   Then wire `[google_monitoring_notification_channel.email.name]` into all `notification_channels` fields at lines 21, 47, 117, 148.

8. **Move SMTP_USER to Secret Manager.** In `cloud-run.tf:33-35`, replace the plaintext env var with a secret reference. Create the secret resource if it doesn't exist.

## When done

Run `terraform plan` and paste the output summary into your commit message. Commit to `claude/security-fixes` branch. Do NOT run `terraform apply`. Do NOT merge to main.
