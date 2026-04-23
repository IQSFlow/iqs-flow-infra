# Marketing forms handler — runbook

**Purpose:** Capture contact, newsletter, and job-application form submissions from `iqsflow.com` via a Cloud Function and deliver them to `sales@iqsflow.com`.

## Architecture

```
iqsflow.com/api/forms/submit  (LB path matcher)
    ↓
serverless NEG  marketing-forms-neg
    ↓
Cloud Function  marketing-forms-handler  (Gen 2, us-central1)
    ↓
  ├── Verify reCAPTCHA v3 token (secret from Secret Manager)
  ├── Validate payload (Zod)
  ├── Log structured submission to Cloud Logging (searchable backup)
  └── Send email via Gmail API (DWD impersonation → sales@iqsflow.com)
```

- **No database.** Primary record is the email; searchable backup is Cloud Logging.
- **Impersonation target:** `IMPERSONATE_USER` env var (default `jhinton@iqsflow.com`). Change to `noreply@iqsflow.com` if/when that Workspace user is created.
- **Recipient:** `TO_EMAIL` env var (default `sales@iqsflow.com`, a Google Group).

## One-time setup

### 1. Run the infra setup script

```bash
cd c:/Users/joshu/Flow/iqs-flow-infra/scripts
./marketing-forms-setup.sh
```

Creates:
- Service account `marketing-forms@crested-booking-488922-f7.iam.gserviceaccount.com`
- Empty Secret Manager secret `recaptcha-v3-secret`
- Enables Gmail API, Secret Manager, Cloud Functions, Cloud Run, Cloud Build

At the end it prints the SA's OAuth2 client ID. Copy that — you need it in step 3.

### 2. Register reCAPTCHA v3

1. Visit https://www.google.com/recaptcha/admin/create
2. Label: `iqsflow.com marketing forms`
3. Type: **reCAPTCHA v3**
4. Domains: `iqsflow.com`, `www.iqsflow.com`
5. Accept the terms, submit.
6. Copy the **site key** (public) and **secret key** (private).

### 3. Grant domain-wide delegation in Google Workspace

Requires Workspace admin access (you have it).

1. Go to https://admin.google.com
2. **Security → Access and data control → API controls**
3. Click **Domain-wide delegation**
4. **Add new**
5. **Client ID:** paste the OAuth2 client ID printed by setup.sh
6. **OAuth scopes:** `https://www.googleapis.com/auth/gmail.send`
7. Authorize

### 4. Store the reCAPTCHA secret key

```bash
printf '<paste secret key>' | gcloud secrets versions add recaptcha-v3-secret \
  --project=crested-booking-488922-f7 --data-file=-
```

### 5. Paste the site key into the site

Edit `iqs-flow-marketing/site/assets/config.js` — replace `PASTE_RECAPTCHA_V3_SITE_KEY_HERE` with the site key from step 2.

### 6. Deploy the function

```bash
cd c:/Users/joshu/Flow/iqs-flow-marketing/functions/forms-handler
IMPERSONATE_USER=jhinton@iqsflow.com ./deploy.sh
```

First deploy takes ~2 minutes. Prints the Cloud Run URL on success. You can test directly:

```bash
curl -X POST https://<FUNCTION_URL>/ \
  -H "Content-Type: application/json" \
  -d '{"form_type":"contact","token":"test","email":"test@example.com","message":"test"}'
# Expect: 400 failed_bot_check (reCAPTCHA rejected)
```

### 7. Wire the LB path matcher

```bash
cd c:/Users/joshu/Flow/iqs-flow-infra/scripts
./marketing-forms-lb-wire.sh
```

Adds `/api/forms/*` routing to `iqs-flow-urlmap`. After this, `iqsflow.com/api/forms/submit` reaches the function.

### 8. Verify end-to-end

1. Open https://iqsflow.com/contact.html (or the bucket-direct URL if cutover hasn't happened)
2. Submit the form with real fields
3. Check `sales@iqsflow.com` for the message
4. Check Cloud Logging: filter `logName=~"marketing-forms-handler" jsonPayload.formType="contact"` — you should see the structured submission log

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `400 failedPrecondition` from Gmail | DWD impersonation silently failed; the SA token was used as-is and a service account can't have a Gmail mailbox | Confirm `getImpersonatedAccessToken()` (signJwt + JWT-bearer exchange) is being used — NOT `google.auth.GoogleAuth({ clientOptions: { subject } })`, which only does DWD when a private key is on disk. Also confirm the SA has `roles/iam.serviceAccountTokenCreator` on itself. |
| `403 IAM_PERMISSION_DENIED` from Gmail | Domain-wide delegation not configured or wrong scope | Re-check step 3 — Client ID + scope |
| `failed_bot_check` on every submit | Site key / secret mismatch, or domains not authorized | Re-check reCAPTCHA admin config; redeploy secret |
| `missing_recaptcha_token` | Script loading order broken on the page | Check `config.js` loads BEFORE `shared.js` |
| Emails send but never arrive at sales@ | Google Group inbound filter rejecting | Check group settings: "Who can post" must include the impersonated user |
| Submissions logged but no email | SA lost DWD access | Re-authorize in Workspace admin |

## Rollback

If forms misbehave in production and you can't fix quickly:

```bash
# Disable the path matcher by removing the host rule (simplest)
gcloud compute url-maps remove-host-rule iqs-flow-urlmap \
  --project=crested-booking-488922-f7 \
  --host=iqsflow.com,www.iqsflow.com
```

Forms will return 404. The static site continues to serve. Re-add the path matcher after fixing.

## Cost

- Cloud Function: free tier covers ~2M invocations/month; forms traffic is far below this
- Secret Manager: $0.06/month per secret
- Serverless NEG + backend service: free
- LB traffic: already paid for existing LB
- Cloud Logging: free at this volume
- **Net ongoing cost: ~$0.06/month**

## Adding a new form type later

1. Add a new HTML form with `class="iqs-form"` and `data-form-type="your-new-type"`.
2. Add the new type to `FORM_LABEL` in `functions/forms-handler/index.js`.
3. Redeploy the function: `./deploy.sh`.
4. No LB changes needed.
