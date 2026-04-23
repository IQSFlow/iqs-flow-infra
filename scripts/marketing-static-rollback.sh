#!/usr/bin/env bash
#
# Instant rollback: flip iqs-flow-urlmap default backend back to the old
# Cloud Run marketing backend service. Use this if the static cutover
# broke anything and you need iqsflow.com serving again NOW.
#
# Runs in seconds. DNS unchanged. SSL cert unchanged.

set -euo pipefail

PROJECT_ID="crested-booking-488922-f7"
URL_MAP="iqs-flow-urlmap"
OLD_BACKEND="iqs-flow-backend"

echo "==> Reverting URL map ${URL_MAP} default backend → backend-service ${OLD_BACKEND}"
gcloud compute url-maps set-default-service "${URL_MAP}" \
  --project="${PROJECT_ID}" \
  --default-service="${OLD_BACKEND}"

echo ""
echo "==> Rollback complete. Verifying..."
gcloud compute url-maps describe "${URL_MAP}" \
  --project="${PROJECT_ID}" \
  --format="value(defaultService)"

echo ""
echo "iqsflow.com back on Cloud Run. Check app functional before investigating the static site issue."
