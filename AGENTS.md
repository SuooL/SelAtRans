# SelAtRans development

## Product contract

- Read `docs/REQUIREMENTS.md` before changing behavior.
- Native macOS utility; no menu bar or Dock item. The draggable floating indicator
  must never activate the app or translate on a left click.
- Never log user text, translations, API keys, authorization headers, or response bodies.
- Store API keys only in Keychain. Never add credential files or user configuration.

## Branch and PR workflow

- `main` is release-ready; `dev` is the integration branch. Never commit or push
  changes directly to either protected branch, including as an administrator.
- Create `feature/*`, `fix/*`, or `chore/*` from current `origin/dev`.
- Open a PR into `dev`; enable squash automerge after local checks.
- Promote only through a `dev` → `main` PR, using merge-commit automerge so that
  shared ancestry is preserved. Do not squash the release PR.
- Required checks: `Validate`, `Secret scan`, `PR policy`. Do not bypass checks.
- Use `gh` for GitHub operations. Verify remote CI and merged state before
  reporting completion. Delete only clean, merged temporary branches.
- Agent co-authorship must match the actual runtime: Codex, Claude, or DeepSeek.
  Hooks detect Codex/Claude sessions; set `SELATRANS_AGENT=deepseek` for a DeepSeek
  agent without a recognizable runtime marker. Never infer identity from API keys
  or the application's selected translation model. Use `scripts/pr.sh` so squash
  commits retain the same attribution. Never reuse another agent's trailer.
- This is a single-maintainer repository: automated checks gate merge; do not
  describe the process as an independent human code review.

## Verification

- Run `scripts/check.sh` and `scripts/secret-scan.sh` before committing.
- Install local hooks with `git config core.hooksPath .githooks`.
- Use meaningful unit tests for routing, request validation, API error handling,
  and input-change protection. Network tests use synthetic text and fake keys.
- Live API and cross-application Accessibility checks require explicit user
  configuration; never discover credentials from unrelated local applications.
- Keep dependencies minimal. Pin GitHub Actions to commit SHAs.

## Repository bootstrap

The root commit was made on `bootstrap/repository`, then `main` and `dev` were
created at that same commit. All subsequent changes use protected-branch PRs.
