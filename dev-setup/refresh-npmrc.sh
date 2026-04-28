#!/usr/bin/env bash
# refresh-npmrc.sh — refresh the private npm registry token in every IQS Flow repo's .npmrc
#
# The Artifact Registry token expires after ~1 hour. Run this when npm install starts
# returning 403 Forbidden for @iqsflow/shared.
#
# Run: ./refresh-npmrc.sh

set -e

PROJECT_ID="crested-booking-488922-f7"
NPM_REGISTRY_HOST="us-central1-npm.pkg.dev"
NPM_REGISTRY_PATH="iqs-flow-npm"
FLOW_DIR="$HOME/Flow"

REPOS_NEEDING_NPMRC=(
  iqs-flow-shared
  iqs-flow-api
  iqs-flow-web
  iqs-flow-mobile
)

# Ensure gcloud is authenticated
if ! gcloud auth print-access-token >/dev/null 2>&1; then
  echo "Error: gcloud not authenticated. Run: gcloud auth login"
  exit 1
fi

NPM_TOKEN=$(gcloud auth print-access-token)

for repo in "${REPOS_NEEDING_NPMRC[@]}"; do
  REPO_PATH="$FLOW_DIR/$repo"
  if [[ ! -d "$REPO_PATH" ]]; then
    echo "Skipping $repo (not cloned at $REPO_PATH)"
    continue
  fi
  cat > "$REPO_PATH/.npmrc" <<EOF
@iqsflow:registry=https://${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/
//${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/:_authToken=${NPM_TOKEN}
//${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/:always-auth=true
EOF
  echo "✓ Refreshed .npmrc for $repo"
done

echo
echo "Done. Token is good for ~1 hour. Re-run if you hit 403 Forbidden again."
