#!/usr/bin/env bash
#
# Cut iqsflow.com + www.iqsflow.com over from the Cloud Run marketing service
# to the new GCS static bucket. One-line URL map change, reversible in seconds.
#
# BEFORE RUNNING:
#   - marketing-static-setup.sh has already been run
#   - The HTML site has been uploaded to gs://iqsflow-marketing-static/
#   - You have verified index.html and a few sub-pages resolve directly:
#       https://storage.googleapis.com/iqsflow-marketing-static/index.html
#
# What this changes:
#   url-map  iqs-flow-urlmap  default backend → iqsflow-marketing-backend
#
# Everything else (forwarding rules, target proxies, SSL cert, DNS) stays.
# The SSL cert iqs-flow-cert already covers iqsflow.com + www.iqsflow.com.

set -euo pipefail

PROJECT_ID="crested-booking-488922-f7"
URL_MAP="iqs-flow-urlmap"
NEW_BACKEND_BUCKET="iqsflow-marketing-backend"

echo "==> Current URL map default backend:"
gcloud compute url-maps describe "${URL_MAP}" \
  --project="${PROJECT_ID}" \
  --format="value(defaultService)"

echo ""
read -p "Swap to ${NEW_BACKEND_BUCKET}? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

echo "==> Swapping URL map default backend → backend-bucket ${NEW_BACKEND_BUCKET}"
gcloud compute url-maps set-default-service "${URL_MAP}" \
  --project="${PROJECT_ID}" \
  --default-backend-bucket="${NEW_BACKEND_BUCKET}"

echo ""
echo "==> Cutover complete. Verifying..."
gcloud compute url-maps describe "${URL_MAP}" \
  --project="${PROJECT_ID}" \
  --format="value(defaultService)"

echo ""
echo "iqsflow.com + www.iqsflow.com now serve from the GCS static bucket."
echo "LB edge cache TTL is 1h; use Ctrl+Shift+R or curl -H 'Cache-Control: no-cache' for first verification."
echo ""
echo "Rollback (if anything looks wrong):"
echo "  ./marketing-static-rollback.sh"
