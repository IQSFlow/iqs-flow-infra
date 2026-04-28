#!/usr/bin/env bash
# bootstrap-mac.sh — provisions a Mac for IQS Flow development
#
# Idempotent: safe to re-run. Skips steps already complete.
# Run: curl -fsSL https://raw.githubusercontent.com/IQSFlow/iqs-flow-infra/main/dev-setup/bootstrap-mac.sh | bash
# Or:  ./bootstrap-mac.sh

set -e

PROJECT_ID="crested-booking-488922-f7"
REGION="us-central1"
NPM_REGISTRY_HOST="us-central1-npm.pkg.dev"
NPM_REGISTRY_PATH="iqs-flow-npm"
GITHUB_ORG="IQSFlow"
FLOW_DIR="$HOME/Flow"

REPOS=(
  iqs-flow-shared
  iqs-flow-api
  iqs-flow-web
  iqs-flow-mobile
  iqs-flow-infra
  iqs-flow-marketing
)

# Logging helpers
log()   { printf "\033[1;34m▸\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m!\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m✗\033[0m %s\n" "$*"; exit 1; }
ask()   { printf "\033[1;36m?\033[0m %s " "$*"; read -r REPLY; }

# OS check
if [[ "$(uname)" != "Darwin" ]]; then
  warn "Not on macOS. Some Homebrew steps may fail. Continuing anyway..."
fi

# 1. Homebrew
if ! command -v brew &>/dev/null; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add to PATH for Apple Silicon
  if [[ -d "/opt/homebrew/bin" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  ok "Homebrew already installed"
fi

# 2. Tools via Homebrew
log "Installing CLI tools"
BREW_PACKAGES=(
  node@20
  git
  gh
  python@3.11
  pgcli
  jq
)
for pkg in "${BREW_PACKAGES[@]}"; do
  if brew list --formula | grep -q "^${pkg%@*}$"; then
    ok "$pkg already installed"
  else
    brew install "$pkg"
  fi
done

# Link node@20 if not in PATH
if ! command -v node &>/dev/null; then
  brew link --overwrite node@20
fi

# 3. Google Cloud SDK
if ! command -v gcloud &>/dev/null; then
  log "Installing Google Cloud SDK"
  brew install --cask google-cloud-sdk
else
  ok "gcloud already installed"
fi

# 4. cloud-sql-proxy
if ! command -v cloud-sql-proxy &>/dev/null; then
  log "Installing cloud-sql-proxy"
  if [[ "$(uname -m)" == "arm64" ]]; then
    PROXY_URL="https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.13.0/cloud-sql-proxy.darwin.arm64"
  else
    PROXY_URL="https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.13.0/cloud-sql-proxy.darwin.amd64"
  fi
  sudo curl -o /usr/local/bin/cloud-sql-proxy "$PROXY_URL"
  sudo chmod +x /usr/local/bin/cloud-sql-proxy
else
  ok "cloud-sql-proxy already installed"
fi

# 5. Python deps for psql scripts
log "Installing Python deps (psycopg2)"
python3 -m pip install --user --quiet psycopg2-binary || warn "psycopg2 install failed (continue — only needed for diagnostic scripts)"

# 6. Claude Code CLI
if ! command -v claude &>/dev/null; then
  log "Installing Claude Code CLI"
  curl -fsSL https://claude.ai/install.sh | bash
else
  ok "Claude Code already installed"
fi

# 7. Codex CLI
if ! command -v codex &>/dev/null; then
  log "Installing Codex CLI"
  npm install -g @openai/codex || warn "Codex install failed (manual: see https://github.com/openai/codex)"
else
  ok "Codex already installed"
fi

# 8. Auth — interactive
log "Authenticating gcloud (browser opens)"
if ! gcloud config get-value account 2>/dev/null | grep -q "@"; then
  gcloud auth login
fi
gcloud config set project "$PROJECT_ID"

log "Setting up Application Default Credentials (browser opens)"
if [[ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
  gcloud auth application-default login
fi

log "Authenticating GitHub CLI"
if ! gh auth status &>/dev/null; then
  gh auth login
fi

# 9. Configure git
if [[ -z "$(git config --global user.email)" ]]; then
  git config --global user.email "joshua.hinton93@gmail.com"
  git config --global user.name "jhinton1"
  ok "git user configured"
fi

# 10. Clone repos
log "Cloning repos to $FLOW_DIR"
mkdir -p "$FLOW_DIR"
for repo in "${REPOS[@]}"; do
  if [[ -d "$FLOW_DIR/$repo/.git" ]]; then
    ok "$repo already cloned (pulling latest)"
    git -C "$FLOW_DIR/$repo" pull --quiet
  else
    log "Cloning $repo"
    gh repo clone "$GITHUB_ORG/$repo" "$FLOW_DIR/$repo"
  fi
done

# 11. Configure private npm registry per repo
log "Generating .npmrc per repo"
NPM_TOKEN=$(gcloud auth print-access-token)
for repo in iqs-flow-shared iqs-flow-api iqs-flow-web iqs-flow-mobile; do
  cat > "$FLOW_DIR/$repo/.npmrc" <<EOF
@iqsflow:registry=https://${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/
//${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/:_authToken=${NPM_TOKEN}
//${NPM_REGISTRY_HOST}/${PROJECT_ID}/${NPM_REGISTRY_PATH}/:always-auth=true
EOF
  ok ".npmrc written for $repo"
done

# 12. npm install in each repo
log "Running npm install per repo (this is the longest step)"
for repo in iqs-flow-shared iqs-flow-api iqs-flow-web iqs-flow-mobile; do
  cd "$FLOW_DIR/$repo"
  if [[ -d node_modules ]]; then
    ok "$repo node_modules exists (skipping; run npm ci to refresh)"
  else
    log "npm install in $repo"
    npm install --silent || warn "npm install failed in $repo — see error above"
  fi
done

# 13. Reconstruct .env files from Secret Manager
log "Reconstructing .env files from Secret Manager"

write_secret_to_env() {
  local repo="$1"
  local key="$2"
  local secret="$3"
  local value
  value=$(gcloud secrets versions access latest --secret="$secret" --project="$PROJECT_ID" 2>/dev/null) || {
    warn "Secret $secret not accessible (skipping $key in $repo/.env)"
    return
  }
  echo "${key}=${value}" >> "$FLOW_DIR/$repo/.env.tmp"
}

# api .env
rm -f "$FLOW_DIR/iqs-flow-api/.env.tmp"
echo "NODE_ENV=development" > "$FLOW_DIR/iqs-flow-api/.env.tmp"
echo "PORT=8080" >> "$FLOW_DIR/iqs-flow-api/.env.tmp"
echo 'CORS_ORIGINS=https://app.iqsflow.com,https://iqsflow.com,http://localhost:3000' >> "$FLOW_DIR/iqs-flow-api/.env.tmp"
write_secret_to_env iqs-flow-api DATABASE_URL iqs-flow-db-url
write_secret_to_env iqs-flow-api SESSION_SECRET iqs-flow-session-secret
write_secret_to_env iqs-flow-api SMTP_USER iqs-flow-smtp-user
write_secret_to_env iqs-flow-api SMTP_PASS iqs-flow-smtp-pass
write_secret_to_env iqs-flow-api ADMIN_API_KEY iqs-flow-admin-api-key
write_secret_to_env iqs-flow-api AERODATABOX_API_KEY aerodatabox-api-key
write_secret_to_env iqs-flow-api GOOGLE_MAPS_API_KEY google-maps-api-key
write_secret_to_env iqs-flow-api STRIPE_API_KEY stripe-api-key-dev
mv "$FLOW_DIR/iqs-flow-api/.env.tmp" "$FLOW_DIR/iqs-flow-api/.env"
ok "iqs-flow-api/.env written"

# web .env
rm -f "$FLOW_DIR/iqs-flow-web/.env.tmp"
echo "NODE_ENV=development" > "$FLOW_DIR/iqs-flow-web/.env.tmp"
echo "PORT=3000" >> "$FLOW_DIR/iqs-flow-web/.env.tmp"
write_secret_to_env iqs-flow-web SESSION_SECRET iqs-flow-session-secret
write_secret_to_env iqs-flow-web API_URL iqs-flow-api-url
mv "$FLOW_DIR/iqs-flow-web/.env.tmp" "$FLOW_DIR/iqs-flow-web/.env"
ok "iqs-flow-web/.env written"

# mobile (if needed — check existing file)
if [[ -f "$FLOW_DIR/iqs-flow-mobile/.env.example" ]]; then
  log "Mobile uses .env.example — copy and customize manually"
fi

# 14. VSCode multi-root workspace
log "Generating VSCode workspace"
cat > "$FLOW_DIR/iqs-flow.code-workspace" <<EOF
{
  "folders": [
    { "path": "iqs-flow-shared" },
    { "path": "iqs-flow-api" },
    { "path": "iqs-flow-web" },
    { "path": "iqs-flow-mobile" },
    { "path": "iqs-flow-infra" },
    { "path": "iqs-flow-marketing" },
    { "path": "iqs-flow-design-handoff", "name": "iqs-flow-design-handoff (read-only ref)" }
  ],
  "settings": {
    "files.exclude": {
      "**/node_modules": true,
      "**/.next": true,
      "**/dist": true,
      "**/.terraform": true
    }
  }
}
EOF
ok "VSCode workspace at $FLOW_DIR/iqs-flow.code-workspace"

# 15. ~/.claude config sync prompt
echo
log "Personal Claude Code config (~/.claude/) — Option A: private GitHub repo sync"
echo
ask "Have you created a private GitHub repo for ~/.claude/ and pushed your config from your other machine? (y/N)"
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  ask "What's the repo URL? (e.g., git@github.com:user/joshua-claude-config.git)"
  CLAUDE_CONFIG_REPO="$REPLY"
  if [[ -d "$HOME/.claude" && ! -d "$HOME/.claude/.git" ]]; then
    BACKUP="$HOME/.claude.backup-$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing ~/.claude/ to $BACKUP"
    mv "$HOME/.claude" "$BACKUP"
  fi
  if [[ ! -d "$HOME/.claude/.git" ]]; then
    log "Cloning Claude config"
    git clone "$CLAUDE_CONFIG_REPO" "$HOME/.claude"
  else
    log "Pulling latest Claude config"
    git -C "$HOME/.claude" pull
  fi
else
  warn "Skipping Claude config sync. See README.md → 'Claude Code config sync' for setup."
fi

# 16. Final verification
echo
log "Verification"
node --version | sed 's/^/  node: /'
gcloud --version | head -1 | sed 's/^/  /'
cloud-sql-proxy --version 2>&1 | head -1 | sed 's/^/  /'
gh --version | head -1 | sed 's/^/  /'
command -v claude >/dev/null && echo "  claude: $(claude --version 2>&1 | head -1)" || warn "claude not in PATH"
command -v codex >/dev/null && echo "  codex: installed" || warn "codex not in PATH"
echo
ok "Bootstrap complete. Repos at $FLOW_DIR"
echo
echo "Next steps:"
echo "  1. Open the workspace:    code $FLOW_DIR/iqs-flow.code-workspace"
echo "  2. Verify dev DB access:  see README.md → 'Verification' section"
echo "  3. If npm 403 errors:     ./refresh-npmrc.sh"
echo "  4. Pair-mode worktrees:   ./prime-worktree-npmrc.sh <worktree-path>"
echo
