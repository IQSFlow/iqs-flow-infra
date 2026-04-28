# IQS Flow — Dev environment setup

Bootstraps a fresh machine (Mac primary, Linux compatible) to a working IQS Flow dev environment that matches the desktop you've been working from.

## What you get

- All 6 IQS Flow repos cloned under `~/Flow/`
- All required tools installed (Node 20, gcloud, cloud-sql-proxy, Python, pgcli, gh CLI)
- `gcloud` authenticated to `crested-booking-488922-f7`
- Private npm registry (`iqs-flow-npm` Artifact Registry) configured per repo
- `.env` files reconstructed from Secret Manager
- VSCode multi-root workspace ready
- Claude Code + Codex CLI installed
- Personal `~/.claude/` config synced from a private GitHub repo (separate sync — see Claude config section below)

Total time on a fresh Mac: ~15–20 min if you babysit the gcloud auth prompt; ~5 min unattended after.

## Quick start (Mac)

```bash
# One-line bootstrap (review before running, of course):
curl -fsSL https://raw.githubusercontent.com/IQSFlow/iqs-flow-infra/main/dev-setup/bootstrap-mac.sh | bash
```

Or clone first, then run:

```bash
git clone https://github.com/IQSFlow/iqs-flow-infra.git ~/Flow/iqs-flow-infra
cd ~/Flow/iqs-flow-infra/dev-setup
./bootstrap-mac.sh
```

The script is idempotent — safe to re-run if anything fails partway through.

## What the bootstrap does

1. **Homebrew** — installs if missing, otherwise updates
2. **Tools** — installs `node@20`, `git`, `gh`, `python@3.11`, `pgcli`, `cloud-sql-proxy`, `gcloud` (Google Cloud SDK), `claude-code`, plus `psycopg2-binary` for Python
3. **Codex** — installs the Codex CLI
4. **Auth prompts (interactive — needs your attention):**
   - `gcloud auth login` — opens browser for Google account
   - `gcloud auth application-default login` — second browser prompt for ADC (used by cloud-sql-proxy and the npm registry)
   - `gh auth login` — GitHub CLI auth (use SSH if you have a key, else HTTPS with token)
4. **Repos** — clones all 6 IQS Flow repos under `~/Flow/`
5. **Per-repo setup** — runs `refresh-npmrc.sh` (writes `.npmrc` with a fresh access token), then `npm install` in each repo
6. **`.env` files** — pulls all secrets from Secret Manager and writes the matching `.env` files (api, web, mobile)
7. **VSCode workspace** — generates `~/Flow/iqs-flow.code-workspace` with all 7 directories included (6 repos + design handoff)

## Manual steps not covered by the bootstrap

These are either secrets or external account setups that can't be automated:

### 1. Anthropic API key for Claude Code
Already done if you've used `claude` before on any machine — your account is tied to your email. On first `claude` invocation it'll prompt for browser login.

### 2. Stripe test key (only if you want to test self-service billing on dev)
Pull `stripe-api-key-dev` from Secret Manager:
```bash
gcloud secrets versions access latest --secret=stripe-api-key-dev --project=crested-booking-488922-f7
```
Set as `STRIPE_API_KEY` in `~/Flow/iqs-flow-api/.env`. (The bootstrap does this automatically — listed here so you know.)

### 3. Design handoff bundle
The design handoff at `~/Flow/iqs-flow-design-handoff/` is NOT a git repo per the project decision (it's read-only reference material). Copy it from your desktop manually via cloud sync (Dropbox, iCloud, Google Drive) OR pull a fresh bundle from Claude Design when ready.

### 4. Personal `~/.claude/` config (separate sync — see below)

## Claude Code config sync (Option A: private GitHub repo)

Your global Claude Code config lives outside any project repo at `~/.claude/`. To make it portable across machines, mirror it to a private GitHub repo.

### One-time setup (do this on the desktop FIRST)

```bash
# 1. Create a new PRIVATE GitHub repo
gh repo create joshua-claude-config --private --description "Personal Claude Code config (CLAUDE.md, memory, agents, skills) — DO NOT make public"

# 2. Initialize the repo from your existing config
cd ~/.claude
git init
# Add a .gitignore for things that shouldn't sync (caches, machine-specific tokens)
cat > .gitignore <<'EOF'
# Caches (regenerate per machine)
todos/
projects/*/cache/
projects/*/sessions/
.DS_Store
**/node_modules/

# Plugin-managed (each plugin manages its own)
plugins/cache/

# OAuth / secrets (machine-specific)
.credentials.json
auth.json
EOF
git add -A
git commit -m "initial: claude config snapshot $(date +%Y-%m-%d)"
git remote add origin git@github.com:<your-user>/joshua-claude-config.git
git branch -M main
git push -u origin main
```

### On the MacBook

The bootstrap script will offer to clone this repo into `~/.claude/` when run. Or do it manually:

```bash
# On the new machine:
mv ~/.claude ~/.claude.backup-$(date +%Y%m%d)   # safety net if Mac has a fresh ~/.claude
git clone git@github.com:<your-user>/joshua-claude-config.git ~/.claude
```

### Keeping it in sync

After every meaningful change (new memory, new agent, CLAUDE.md edit):
```bash
cd ~/.claude
git add -A
git commit -m "sync: $(date +%Y-%m-%d)"
git push
```

On the other machine before starting:
```bash
cd ~/.claude
git pull
```

You can automate this with a cron job or a shell alias if it gets tedious — out of scope for the bootstrap.

## Verification (after running bootstrap)

```bash
# All tools present
node --version          # should be v20.x
gcloud --version        # 4xx.x.x
cloud-sql-proxy --version
pgcli --version
gh --version
claude --version

# All repos cloned
ls ~/Flow/                # should show all 6 iqs-flow-* dirs

# .env files exist (don't print contents)
for f in ~/Flow/iqs-flow-api/.env ~/Flow/iqs-flow-web/.env; do
  test -f "$f" && echo "OK: $f" || echo "MISSING: $f"
done

# npm install worked in each repo
for d in ~/Flow/iqs-flow-{api,web,shared,mobile}; do
  test -d "$d/node_modules" && echo "OK: $d node_modules" || echo "MISSING: $d node_modules"
done

# Connect to dev DB (read-only)
cloud-sql-proxy crested-booking-488922-f7:us-central1:iqs-flow-db --port=5432 &
PG_PW=$(gcloud secrets versions access latest --secret=db-readonly-password-dev --project=crested-booking-488922-f7)
PGPASSWORD=$PG_PW pgcli -h 127.0.0.1 -p 5432 -U iqsflow_readonly -d iqsflow -c "SELECT COUNT(*) FROM \"Tenant\""
# kill the proxy: pkill cloud-sql-proxy
```

## Common issues

### `403 Forbidden` from `npm install`
The `.npmrc` token expires after ~1 hour. Run:
```bash
~/Flow/iqs-flow-infra/dev-setup/refresh-npmrc.sh
```

### `gcloud` says "no active account"
Re-run:
```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project crested-booking-488922-f7
```

### Cloud SQL proxy connection fails
Make sure ADC is set up:
```bash
gcloud auth application-default login
```

### Working in a git worktree (parallel agents pattern)
Worktrees don't inherit `.npmrc` (gitignored). Run `prime-worktree-npmrc.sh <worktree-path>` after `git worktree add` and before `npm install`.

## Reference

- **Repos** — see [`bootstrap-mac.sh`](./bootstrap-mac.sh) for the canonical list
- **Secrets** — see your GCP Secret Manager (project `crested-booking-488922-f7`)
- **Workflow** — see global `CLAUDE.md` (in your `~/.claude/` config repo)
- **Per-repo conventions** — `CLAUDE.md` at the root of each repo
