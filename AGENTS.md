# AGENTS.md — IQS Flow two-agent SDLC

This repo runs a two-agent pipeline: **Claude Code** as planner/builder, **Codex** as reviewer/refactor/security gate. Both agents read this file alongside `CLAUDE.md`.

## Role split

| Agent | Role | Authority |
|---|---|---|
| **Claude Code — orchestrator** | Reads bug reports / feature asks. Plans waves across repos. Writes `.claude/tasks/XX-name.md` files. Coordinates dispatch. Owns deploys (tag pushes). | Full |
| **Claude Code — worker** | Picks up tasks via `/check-tasks`. Implements, commits, merges to main, follows the autonomous-task contract in `CLAUDE.md`. | Full within scope of one task |
| **Codex — reviewer** | Reviews diffs after Claude workers commit. Focus: bugs, security, edge cases, duplicated logic, type safety, test coverage, performance. Never adds new features. | Read + minimal refactor patches |

## Where Codex finds work

- **Pending tasks** for Claude workers: `.claude/tasks/XX-name.md` (no `.done.md` sibling).
- **Completed work awaiting Codex review:** branches matching `claude/*` not yet merged to main, OR commits on main with no Codex review note.
- **Repo-specific conventions and architecture:** `CLAUDE.md` at repo root.
- **Per-task intent and acceptance criteria:** the matching `.md` file in `.claude/tasks/`.
- **What the worker actually shipped:** the matching `.done.md` file.

## Codex review protocol

When invited to review (e.g. "Codex, review `claude/00-list-pages-render-new-fields`"):

1. Read the task file (`.claude/tasks/00-*.md`) and `.done.md` to understand intent and what the worker self-reported.
2. Diff the branch against `main`: `git diff main..claude/00-* -- ':!package-lock.json'`.
3. Report under five fixed headings:
   - **Blockers** — must fix before merge (security, correctness, broken contracts).
   - **Recommended refactors** — safe to apply now, no behavior change.
   - **Security concerns** — see multi-tenant safety checklist below.
   - **Test gaps** — missing coverage for the new code paths.
   - **Minimal patch suggestions** — the smallest diffs that address the blockers + security findings.
4. If subsequently invited to apply: only safe refactors and explicit bug fixes. No feature additions. Keep the diff small. Do not change product behavior unless fixing a confirmed bug.

## Multi-tenant safety checklist (Codex must always check on backend diffs)

- Every Prisma query filters by `tenantId` (or has an explicit cross-tenant comment with justification).
- API routes call `requireRole(...)` / `requirePermission(...)` before reading or mutating.
- No tenant ID, user ID, or role is read from client-controlled input without authorization re-check.
- GPS, location, and PII are logged only with explicit business need; never user-identifying coordinates in plaintext.
- Secrets and API keys never appear in source — must come from `process.env` or Secret Manager.
- Tests for new endpoints cover the cross-tenant access denial case (a user from tenant A cannot read tenant B data).

## Coexistence rules

- **Do not both edit the same file at the same time.** Orchestrator (Claude) and Codex coordinate via task files + review reports, not parallel edits.
- **Codex does not run `/check-tasks` autonomously.** Worker Claude owns the task queue; Codex is invited per-diff.
- **Codex does not push tags or trigger deploys.** Claude orchestrator owns the deploy lane (tag pushes, prod promotion).
- **No git config changes, no force-pushes, no `--no-verify`** from either agent.
- **Destructive ops** (DB migrations, secret rotations, prod tag pushes, branch deletions): Codex flags risk, Claude/user authorize and execute.

## Handoff format

When Codex completes a review, write the report into the branch as `.claude/reviews/<branch>.md` (NOT `.done.md` — that's the worker's). Orchestrator reads it before merging. Example:

```
.claude/reviews/claude_00-list-pages-render-new-fields.md
```

When Claude orchestrator merges a branch after Codex review, the merge commit message references the review report:

```
Merge claude/00-list-pages-render-new-fields (Codex review: clean, no blockers)
```

## Codex slash commands (installed at `~/.codex/commands/`)

- **`/review-task <branch>`** — Review one Claude worker branch end-to-end against this protocol. Single-shot; writes report to `.claude/reviews/<branch>.md` on the branch and commits it. Add `--apply` to also apply the listed minimal patches.
- **`/check-reviews`** — Codex equivalent of `/check-tasks`. Auto-pick the next unreviewed `claude/*` branch in this repo, review it, chain to the next. Stops on `BLOCKED` verdict or contract mismatch.
- **`/monitor-reviews`** — Status dashboard across all repos: which branches await review, which are CLEAN/NEEDS_FIXES/BLOCKED, which next actions belong to Codex vs Claude orchestrator.

## When in doubt

- **Codex:** report findings, don't act unless explicitly invited.
- **Claude worker:** merge to main after each task per `feedback_merge_after_task.md`.
- **Claude orchestrator:** re-read `CLAUDE.md` and relevant memory files before dispatching cross-cutting work.
