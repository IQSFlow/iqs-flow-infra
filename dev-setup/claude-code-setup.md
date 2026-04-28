# Claude Code config sync — detailed walkthrough

The bootstrap script offers to sync `~/.claude/` from a private GitHub repo. This file documents the full setup — including what to commit, what to ignore, and how to keep machines in sync.

## Why sync `~/.claude/`?

Your Claude Code config contains:
- `CLAUDE.md` — your global workflow rules (multi-root workspace, dispatch patterns, deploy flows, DB conventions, etc.)
- `projects/<workspace>/memory/` — accumulated project knowledge (~30+ memory files in your case)
- `agents/` — custom agent definitions
- `skills/` — installed skills (some are plugin-managed, some are personal)
- `keybindings.json` — custom keyboard shortcuts
- Plugin marketplace state

Without sync, every machine starts from a blank Claude Code experience. With sync, your MacBook on the road has the same memory, same workflow rules, same agents as your desktop.

## One-time setup on the desktop (before first sync)

### Step 1. Create the private repo

```bash
gh repo create joshua-claude-config --private \
  --description "Personal Claude Code config — DO NOT make public"
```

(If you don't have `gh` set up, do this on github.com manually — make sure it's PRIVATE.)

### Step 2. Initialize from your existing config

```bash
cd ~/.claude
git init
```

### Step 3. Add a `.gitignore`

This excludes machine-specific caches, OAuth tokens, and large transient state.

```bash
cat > .gitignore <<'EOF'
# Caches & transient state (regenerate per machine)
todos/
projects/*/cache/
projects/*/sessions/
projects/*/temp/
projects/*/scheduled_tasks.lock
.DS_Store
**/node_modules/

# Plugin-managed state (each plugin manages its own)
plugins/cache/
plugins/repos/

# Machine-specific tokens / OAuth
.credentials.json
auth.json
*.pem
*.key

# Settings.local — machine-specific permissions
**/settings.local.json
EOF
```

### Step 4. First commit + push

```bash
git add .gitignore CLAUDE.md
# Selectively add what you want to sync
git add agents/ skills/ keybindings.json 2>/dev/null || true

# Memory files for the IQS Flow workspace
git add 'projects/c--Users-joshu-Flow-iqs-flow-shared/memory/' 2>/dev/null || true

# Look at what's about to be committed BEFORE pushing — make sure no secrets snuck in
git status
git diff --cached --stat
# If you see anything sensitive, git rm --cached <file> before committing

git commit -m "initial: claude config snapshot $(date +%Y-%m-%d)"

# Set the remote (replace <user> with your GitHub username)
git remote add origin git@github.com:<user>/joshua-claude-config.git
git branch -M main
git push -u origin main
```

### Step 5. Verify the repo is private on GitHub

Go to `https://github.com/<user>/joshua-claude-config/settings`. Confirm "Public" is NOT selected.

## On the MacBook (or any new machine)

The bootstrap script will offer to clone this repo for you. If you skipped that or want to do it manually:

```bash
# Safety: backup the fresh ~/.claude that ships with Claude Code
mv ~/.claude ~/.claude.backup-$(date +%Y%m%d) 2>/dev/null || true

# Clone your config
git clone git@github.com:<user>/joshua-claude-config.git ~/.claude

# Test that Claude Code picks it up
claude --help
```

The next `claude` invocation will see your global CLAUDE.md, memory files, and skills.

## Day-to-day sync

After meaningful changes (new memory entry, edited CLAUDE.md, new agent):

```bash
cd ~/.claude
git add -A
git commit -m "sync: $(date +%Y-%m-%d): <what changed>"
git push
```

On the other machine before starting:

```bash
cd ~/.claude
git pull
```

### Optional: shell aliases for fast sync

Add to `~/.zshrc` or `~/.bashrc`:

```bash
alias claude-pull='git -C ~/.claude pull'
alias claude-push='cd ~/.claude && git add -A && git commit -m "sync: $(date +%Y-%m-%d-%H%M%S)" && git push && cd -'
```

Then `claude-pull` at the start of a session, `claude-push` at the end.

## What can go wrong

### Conflict on memory file
You edit a memory on machine A, edit the same memory on machine B before pulling. Standard git merge conflict — resolve by hand, prefer the newer/richer version.

### Stale memory on the new machine
Memories reference paths, branches, and commit SHAs. If you sync a memory that says "the v5.17.33 deploy is healthy" and you're on a MacBook months later, that memory is stale. Trust git history (commit dates) and the codebase, not memory content, when in doubt.

### Plugin skills don't carry
Plugin-managed skills (under `plugins/`) are gitignored because they live in their own repos. Re-install plugins on the new machine via Claude Code's plugin marketplace if needed.

### `~/.claude/` already exists with content
The bootstrap backs it up as `~/.claude.backup-YYYYMMDD`. After verifying the cloned config works, delete the backup to reclaim space:
```bash
rm -rf ~/.claude.backup-*
```

## What NOT to commit

If any of these end up tracked, IMMEDIATELY untrack them and rotate the affected token/key:

- `.credentials.json` (OAuth)
- Any file containing an Anthropic API key (`sk-ant-...`)
- Any file containing a Stripe key (`sk_test_...` or `sk_live_...`)
- GCP service account JSON files (`*-service-account.json`)
- SSH private keys (`id_rsa`, `*.pem`, `*.key`)
- Any `.env` file from a project (those go in the project's gitignore)

The default `.gitignore` from Step 3 catches most of these. Audit before pushing if you're unsure:
```bash
git diff --cached --stat | grep -iE "key|cred|token|secret|\.env"
```

## Alternative: shallow share (read-only on MacBook)

If you don't want to sync writes from the MacBook (e.g., it's only for reading code on the road), make the local clone read-only:

```bash
cd ~/.claude
git config branch.main.pushRemote no_push
```

Then nothing accidentally gets pushed from the MacBook. You'd still pull updates from the desktop.
