#!/usr/bin/env bash
#
# Provision everything the marketing forms handler needs, EXCEPT the
# Workspace domain-wide delegation step (which must be done in the
# Google Workspace Admin console by hand).
#
# What this creates:
#   - Service account                marketing-forms@PROJECT.iam.gserviceaccount.com
#   - Secret Manager secret          recaptcha-v3-secret (empty; user pastes value)
#   - IAM: SA can read that secret
#   - IAM: SA can write logs (default, no-op)
#   - Enables: gmail.googleapis.com, secretmanager.googleapis.com, cloudfunctions.googleapis.com, run.googleapis.com
#
# What this does NOT do (run these after):
#   - Deploy the function                  iqs-flow-marketing/functions/forms-handler/deploy.sh
#   - Create serverless NEG + backend      marketing-forms-lb-wire.sh (separate, after function is up)
#   - Enable Workspace domain-wide delegation (manual — see runbook)
#   - Store the reCAPTCHA secret value (manual — see runbook)

set -euo pipefail

PROJECT_ID="crested-booking-488922-f7"
SA_NAME="marketing-forms"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
SECRET_NAME="recaptcha-v3-secret"

echo "==> Using project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" --quiet

# ---- Enable required APIs --------------------------------------------------

echo "==> Enabling APIs (idempotent)"
gcloud services enable \
  gmail.googleapis.com \
  secretmanager.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  --project="${PROJECT_ID}"

# ---- Service account -------------------------------------------------------

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Service account ${SA_EMAIL} already exists"
else
  echo "==> Creating service account ${SA_EMAIL}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Marketing forms handler" \
    --description="Cloud Function SA. Impersonates a Workspace user via DWD to send form-submission emails."
fi

echo ""
echo "==> Service account OAuth2 client ID (needed for Workspace DWD):"
SA_CLIENT_ID=$(gcloud iam service-accounts describe "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --format="value(oauth2ClientId)")
echo "    ${SA_CLIENT_ID}"

# ---- Secret Manager -------------------------------------------------------

if gcloud secrets describe "${SECRET_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Secret ${SECRET_NAME} already exists"
else
  echo "==> Creating secret ${SECRET_NAME} (empty — you'll paste the reCAPTCHA secret next)"
  gcloud secrets create "${SECRET_NAME}" \
    --project="${PROJECT_ID}" \
    --replication-policy=automatic
fi

echo "==> Granting SA read access on ${SECRET_NAME}"
gcloud secrets add-iam-policy-binding "${SECRET_NAME}" \
  --project="${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null

# ---- Summary + manual steps ----------------------------------------------

echo ""
echo "=============================================================="
echo " Setup complete. Three manual steps before deploying."
echo "=============================================================="
echo ""
echo " STEP 1 — Store the reCAPTCHA v3 secret key in Secret Manager:"
echo ""
echo "   printf 'YOUR_RECAPTCHA_SECRET' | gcloud secrets versions add \\"
echo "     ${SECRET_NAME} --project=${PROJECT_ID} --data-file=-"
echo ""
echo " STEP 2 — Grant domain-wide delegation in Google Workspace Admin:"
echo ""
echo "   a. Go to https://admin.google.com"
echo "   b. Security → Access and data control → API controls"
echo "   c. Domain-wide delegation → Add new"
echo "   d. Client ID:    ${SA_CLIENT_ID}"
echo "   e. OAuth scope:  https://www.googleapis.com/auth/gmail.send"
echo "   f. Authorize"
echo ""
echo " STEP 3 — Deploy the function:"
echo ""
echo "   cd c:/Users/joshu/Flow/iqs-flow-marketing/functions/forms-handler"
echo "   IMPERSONATE_USER=jhinton@iqsflow.com ./deploy.sh"
echo ""
echo " Then run marketing-forms-lb-wire.sh to add the /api/forms/* path"
echo " matcher on the existing load balancer."
