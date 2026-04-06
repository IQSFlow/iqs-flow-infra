# Security Fixes Design — 2026-04-05

9 findings from the security audit at `iqs-flow-shared/.security-reports/sec-ship-2026-04-05-201929.md`.

## Approach

Single branch (`claude/security-fixes`), all 9 fixes. No new resources except one Secret Manager secret and one notification channel. `terraform plan` before any apply.

## Changes

### CRITICAL

| # | ID | File | Change |
|---|-----|------|--------|
| 1 | SEC-INFRA-001 | cloud-sql.tf | Set `ipv4_enabled = false` — Cloud Run uses Auth Proxy via Unix socket |
| 2 | SEC-INFRA-002 | cloud-sql.tf | Add `ssl_mode = "ENCRYPTED_ONLY"` to `ip_configuration` |

### HIGH

| # | ID | File | Change |
|---|-----|------|--------|
| 3 | SEC-INFRA-004 | storage.tf | Delete `public_read` IAM binding (`allUsers` objectViewer). API will need signed-URL endpoint added separately. |
| 4 | SEC-INFRA-005 | iam.tf | Replace project-level `serviceAccountUser` with SA-level bindings on `api` and `web` service accounts |
| 5 | SEC-INFRA-006 | iam.tf | Replace project-level `run.developer` with service-level bindings on `api` and `web` Cloud Run services |
| 6 | SEC-INFRA-007 | cloud-sql.tf | Set `point_in_time_recovery_enabled = true` |

### MEDIUM

| # | ID | File | Change |
|---|-----|------|--------|
| 7 | SEC-INFRA-009 | monitoring.tf | Add `google_monitoring_notification_channel` (email: jhinton@iqsflow.com), wire into all 4 alert policies |
| 8 | SEC-INFRA-011 | cloud-run.tf | No-op: image tag is cosmetic since `lifecycle { ignore_changes }` is set. Add comment documenting this. |
| 9 | SEC-INFRA-014 | cloud-run.tf | Add `smtp_user` secret to Secret Manager, reference in Cloud Run env instead of plaintext |

## Risks

- **SEC-INFRA-004**: Removes public bucket access. Direct file URLs will break until API gets a signed-URL endpoint (tracked separately).
- **SEC-INFRA-005/006**: Terraform will destroy old project-level binding and create new resource-level binding. Cloud Build may briefly lose permissions during apply window.
- **SEC-INFRA-001**: Disabling public IP is safe for Cloud Run (Auth Proxy). If external DB tools (pgAdmin, DBeaver) connect via public IP, they will break.

## Follow-up (out of scope)

- Add signed-URL endpoint to `iqs-flow-api` for serving uploaded files
- Set `smtp_user` secret value via `gcloud secrets versions add`
