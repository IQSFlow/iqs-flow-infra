#!/usr/bin/env bash
#
# Wire the deployed marketing-forms-handler Cloud Function into the
# existing load balancer so iqsflow.com/api/forms/submit goes to the
# function while iqsflow.com/* continues to serve the GCS bucket.
#
# Run AFTER:
#   1. marketing-forms-setup.sh (creates SA, secret, enables APIs)
#   2. Workspace domain-wide delegation granted
#   3. reCAPTCHA secret stored in Secret Manager
#   4. forms-handler function deployed (./deploy.sh in functions/forms-handler/)
#
# This script:
#   - Creates a serverless NEG pointing at the deployed Cloud Function
#   - Creates a backend service using that NEG
#   - Adds a path matcher on iqs-flow-urlmap routing /api/forms/* to the function

set -euo pipefail

PROJECT_ID="crested-booking-488922-f7"
REGION="us-central1"
FUNCTION_NAME="marketing-forms-handler"
NEG_NAME="marketing-forms-neg"
BACKEND_SERVICE="marketing-forms-backend"
URL_MAP="iqs-flow-urlmap"
PATH_MATCHER_NAME="forms-routes"

# ---- Verify the function exists -------------------------------------------

if ! gcloud functions describe "${FUNCTION_NAME}" --project="${PROJECT_ID}" --region="${REGION}" --gen2 >/dev/null 2>&1; then
  echo "ERROR: Cloud Function ${FUNCTION_NAME} not deployed in ${REGION}."
  echo "Deploy it first: cd iqs-flow-marketing/functions/forms-handler && ./deploy.sh"
  exit 1
fi

# ---- Serverless NEG -------------------------------------------------------

if gcloud compute network-endpoint-groups describe "${NEG_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> NEG ${NEG_NAME} already exists"
else
  echo "==> Creating serverless NEG ${NEG_NAME} -> ${FUNCTION_NAME}"
  gcloud compute network-endpoint-groups create "${NEG_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --network-endpoint-type=serverless \
    --cloud-function-name="${FUNCTION_NAME}"
fi

# ---- Backend service ------------------------------------------------------

if gcloud compute backend-services describe "${BACKEND_SERVICE}" --project="${PROJECT_ID}" --global >/dev/null 2>&1; then
  echo "==> Backend service ${BACKEND_SERVICE} already exists"
else
  echo "==> Creating backend service ${BACKEND_SERVICE}"
  gcloud compute backend-services create "${BACKEND_SERVICE}" \
    --project="${PROJECT_ID}" \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED
  gcloud compute backend-services add-backend "${BACKEND_SERVICE}" \
    --project="${PROJECT_ID}" \
    --global \
    --network-endpoint-group="${NEG_NAME}" \
    --network-endpoint-group-region="${REGION}"
fi

# ---- URL map path matcher -------------------------------------------------

echo ""
echo "==> Current URL map state:"
gcloud compute url-maps describe "${URL_MAP}" \
  --project="${PROJECT_ID}" \
  --format="yaml(defaultService,hostRules,pathMatchers[].name)" | head -30

echo ""
echo "==> Adding /api/forms/* path matcher"
echo "    This is a one-time add. Re-running may error; edit the URL map manually if so."
read -p "Proceed? [y/N] " -n 1 -r; echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Add a host rule for iqsflow.com + www.iqsflow.com if not already present,
# with a path matcher that routes /api/forms/* to the forms backend and
# everything else to the default (which will be the static bucket after cutover).
# Detect whether the URL map default is a backend service or backend bucket
# (cutover to GCS changes the default from service -> bucket; either must be
# preserved as the matcher's fallback so non-/api/forms paths continue to resolve).
CURRENT_DEFAULT_URL=$(gcloud compute url-maps describe "${URL_MAP}" --project="${PROJECT_ID}" --format='value(defaultService)')
CURRENT_DEFAULT_NAME=$(basename "${CURRENT_DEFAULT_URL}")
if [[ "${CURRENT_DEFAULT_URL}" == *"/backendBuckets/"* ]]; then
  DEFAULT_FLAG="--default-backend-bucket=${CURRENT_DEFAULT_NAME}"
else
  DEFAULT_FLAG="--default-service=${CURRENT_DEFAULT_NAME}"
fi
echo "==> Using matcher default: ${DEFAULT_FLAG}"

gcloud compute url-maps add-path-matcher "${URL_MAP}" \
  --project="${PROJECT_ID}" \
  --path-matcher-name="${PATH_MATCHER_NAME}" \
  ${DEFAULT_FLAG} \
  --backend-service-path-rules="/api/forms/*=${BACKEND_SERVICE}" \
  --new-hosts="iqsflow.com,www.iqsflow.com" || {
    echo "If this failed because the hosts are already claimed by another path matcher,"
    echo "edit the URL map YAML manually:"
    echo "  gcloud compute url-maps export ${URL_MAP} --destination=/tmp/urlmap.yaml"
    echo "  # edit /tmp/urlmap.yaml to add /api/forms/* -> ${BACKEND_SERVICE} under the existing matcher"
    echo "  gcloud compute url-maps import ${URL_MAP} --source=/tmp/urlmap.yaml"
    exit 1
  }

echo ""
echo "==> Done. iqsflow.com/api/forms/submit now reaches the Cloud Function."
echo "    Test: curl -I https://iqsflow.com/api/forms/submit  -> expect 405 (POST only)"
