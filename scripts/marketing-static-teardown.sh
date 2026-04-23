#!/usr/bin/env bash
#
# Decommission the old Cloud Run marketing service AFTER you have verified
# the static site is serving cleanly on iqsflow.com for at least 24 hours.
#
# Irreversible (you would need to redeploy the Next.js marketing repo to
# recover). Run only once the new static site has been in production long
# enough to trust.
#
# What this removes:
#   - Cloud Run service       iqs-flow-marketing
#   - Backend service         iqs-flow-backend       (orphaned after cutover)
#   - Network endpoint group  (associated NEG, if any)
#
# What this keeps:
#   - Load balancer, URL map, SSL cert (still needed for static bucket)
#   - Cloud Build trigger for iqs-flow-marketing repo (repurposed for rsync)

set -euo pipefail

PROJECT_ID="crested-booking-488922-f7"
REGION="us-central1"
CLOUD_RUN_SERVICE="iqs-flow-marketing"
OLD_BACKEND_SERVICE="iqs-flow-backend"

echo "==> Confirming URL map is NOT pointing at ${OLD_BACKEND_SERVICE}..."
CURRENT_DEFAULT=$(gcloud compute url-maps describe iqs-flow-urlmap \
  --project="${PROJECT_ID}" \
  --format="value(defaultService)")
if [[ "${CURRENT_DEFAULT}" == *"${OLD_BACKEND_SERVICE}"* ]]; then
  echo "ERROR: URL map still points at ${OLD_BACKEND_SERVICE}. Run cutover first."
  exit 1
fi
echo "    Safe to proceed."

echo ""
read -p "Permanently delete ${CLOUD_RUN_SERVICE} + ${OLD_BACKEND_SERVICE}? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Find NEG(s) attached to the old backend service before deleting it
NEGS=$(gcloud compute backend-services describe "${OLD_BACKEND_SERVICE}" \
  --project="${PROJECT_ID}" --global \
  --format="value(backends[].group)" 2>/dev/null | tr ';' '\n' | grep -oE '[^/]+$' || true)

echo "==> Deleting backend service ${OLD_BACKEND_SERVICE}"
gcloud compute backend-services delete "${OLD_BACKEND_SERVICE}" \
  --project="${PROJECT_ID}" --global --quiet

for NEG in ${NEGS}; do
  echo "==> Deleting network endpoint group ${NEG}"
  gcloud compute network-endpoint-groups delete "${NEG}" \
    --project="${PROJECT_ID}" --region="${REGION}" --quiet 2>/dev/null || \
  gcloud compute network-endpoint-groups delete "${NEG}" \
    --project="${PROJECT_ID}" --global --quiet 2>/dev/null || \
  echo "    (NEG ${NEG} already gone or not regional/global, skipping)"
done

echo "==> Deleting Cloud Run service ${CLOUD_RUN_SERVICE}"
gcloud run services delete "${CLOUD_RUN_SERVICE}" \
  --project="${PROJECT_ID}" --region="${REGION}" --quiet

echo ""
echo "==> Teardown complete."
echo ""
echo "Follow up: the Cloud Build trigger that used to build iqs-flow-marketing"
echo "needs updating to use gsutil rsync instead of docker build + deploy."
echo "See iqs-flow-marketing/cloudbuild.yaml (replaced as part of the repo rewrite)."
