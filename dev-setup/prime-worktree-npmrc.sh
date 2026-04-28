#!/usr/bin/env bash
# prime-worktree-npmrc.sh — write a fresh .npmrc into a git worktree
#
# When you create a git worktree (for parallel agent work, pair-mode tasks, etc.),
# the new worktree directory does NOT inherit .npmrc from the primary working tree
# because .npmrc is gitignored. This script primes a fresh .npmrc with a current
# gcloud access token.
#
# Run: ./prime-worktree-npmrc.sh <path-to-worktree>
# Example: ./prime-worktree-npmrc.sh ~/Flow/iqs-flow-web-codex/redesign-feature

set -e

PROJECT_ID="crested-booking-488922-f7"
NPM_REGISTRY_HOST="us-central1-npm.pkg.dev"
NPM_REGISTRY_PATH="iqs-flow-npm"

if [[ -z "$1" ]]; then
  echo "Usage: $0 <path-to-worktree>"
  echo "Example: $0 ~/Flow/iqs-flow-web-codex/redesign-feature"
  exit 1
fi

WORKTREE_PATH="$1"

if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "Error: $WORKTREE_PATH does not exist"
  exit 1
fi

# Ensure gcloud is authenticated
if ! gcloud auth print-access-token >/dev/null 2>&1; then
  echo "Error: gcloud not authenticated. Run: gcloud auth login"
  exit 1
fi

NPM_TOKEN=$(gcloud auth print-access-token)

cat > "$WORKTREE_PATH/.npmrc" <<EOF
@iqsflow:registry=https://${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/
//${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/:_authToken=${NPM_TOKEN}
//${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/:always-auth=true
EOF

echo "✓ Primed .npmrc at $WORKTREE_PATH"
echo "  Token good for ~1 hour. Run npm install now."
