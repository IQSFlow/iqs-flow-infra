#!/usr/bin/env bash
#
# Provision GCS + Cloud CDN backend for the new static marketing site.
# Idempotent: re-running is safe; it will skip resources that already exist.
#
# This script does NOT touch the existing URL map, so iqsflow.com continues
# serving from the current Cloud Run backend until you run marketing-static-cutover.sh.
#
# Prerequisites:
#   - gcloud auth active with project crested-booking-488922-f7
#   - Roles: Storage Admin, Compute Network Admin
#
# What this creates:
#   - GCS bucket                gs://iqsflow-marketing-static
#   - Backend bucket            iqsflow-marketing-backend (attached to Cloud CDN)
#
# Ordering:
#   1. setup.sh    (this script)        safe anytime
#   2. rsync HTML  (manual, after site lands)
#   3. cutover.sh  (swap URL map)       the visible change
#   4. teardown.sh (remove old Cloud Run) after verify

set -euo pipefail

PROJECT_ID="crested-booking-488922-f7"
REGION="us-central1"
BUCKET_NAME="iqsflow-marketing-static"
BACKEND_BUCKET="iqsflow-marketing-backend"

echo "==> Using project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" --quiet

# ---- GCS bucket -----------------------------------------------------------

if gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Bucket gs://${BUCKET_NAME} already exists, skipping create"
else
  echo "==> Creating bucket gs://${BUCKET_NAME}"
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention=inherited
fi

echo "==> Granting public read on bucket"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="allUsers" \
  --role="roles/storage.objectViewer" \
  --project="${PROJECT_ID}" >/dev/null

echo "==> Setting website configuration (index.html + 404.html)"
gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --web-main-page-suffix=index.html \
  --web-error-page=404.html \
  --project="${PROJECT_ID}"

# ---- LB backend bucket + Cloud CDN ---------------------------------------

if gcloud compute backend-buckets describe "${BACKEND_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Backend bucket ${BACKEND_BUCKET} already exists, skipping create"
else
  echo "==> Creating LB backend bucket ${BACKEND_BUCKET} with Cloud CDN enabled"
  gcloud compute backend-buckets create "${BACKEND_BUCKET}" \
    --project="${PROJECT_ID}" \
    --gcs-bucket-name="${BUCKET_NAME}" \
    --enable-cdn \
    --cache-mode=CACHE_ALL_STATIC \
    --default-ttl=3600 \
    --max-ttl=86400 \
    --client-ttl=3600 \
    --negative-caching
fi

echo ""
echo "==> Setup complete."
echo ""
echo "Bucket:          gs://${BUCKET_NAME}"
echo "Backend bucket:  ${BACKEND_BUCKET}"
echo "Cloud CDN:       enabled (3600s default TTL)"
echo ""
echo "Next step: upload your site, then run marketing-static-cutover.sh"
echo "  gsutil -m rsync -d -r ./site/ gs://${BUCKET_NAME}/"
