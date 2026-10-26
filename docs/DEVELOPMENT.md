# Development workflow

The default branch is `dev`. Protected branches:

```text
main ← release PR (merge commit) ← dev ← feature PR (squash) ← feature/*
```

`main` and `dev` require a PR, current-base CI, resolved conversations, and the
three checks `Validate`, `Secret scan`, and `PR policy`. Administrators are also
subject to protection. Force pushes and deletion are disabled.
GitHub automatically deletes merged feature/fix/hotfix/chore branches. Protected
`main` and `dev` are retained, including after release PRs. Remove local temporary
branches only after confirming successful remote merge and no remaining work.

The repository permits auto-merge. Each PR opts into auto-merge using `gh pr
merge --auto --squash` for a feature or `gh pr merge --auto --merge` for a release.
No privileged workflow executes untrusted PR code. A zero-reviewer requirement
supports a single maintainer; passing CI is not independent human review.

```sh
git fetch origin
git switch -c feature/my-change origin/dev
git config core.hooksPath .githooks
scripts/check.sh
scripts/secret-scan.sh
git add <specific-files>
git diff --cached --check
git commit -m 'feat: describe the resulting behavior'
git push -u origin HEAD
scripts/pr.sh dev 'feat: describe the resulting behavior' /tmp/pr.md
gh pr merge --auto --squash
gh pr checks --watch
```

PR titles use `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `ci:`, or `release:`.
The complete local gate is `scripts/check.sh` plus `scripts/secret-scan.sh`.
`check.sh` validates shell syntax, workflow/version rules, whitespace, the core
checks, a production build, and signed app packaging. It requires macOS Command
Line Tools, Python 3, and network access for pinned build dependencies.

## Agent attribution

The `prepare-commit-msg` hook appends the actual agent's `Co-authored-by` trailer.
Detection uses session markers, never a provider API key or translation model.
Codex and Claude runtimes are recognized automatically; for other launchers set
`SELATRANS_AGENT=codex`, `claude`, or `deepseek` explicitly. Conflicting markers fail
instead of guessing. No marker means no agent trailer on a manual human commit.
Known stale agent trailers are replaced while human co-authors are preserved.

Use `scripts/pr.sh BASE TITLE BODY_FILE` to create a PR. It appends the matching
trailer without modifying the source body file. The repository's squash message
setting uses the PR body, preserving attribution after feature merge. The
`commit-msg` hook verifies attribution; tests cover all three supported agents.

Secret scanning uses checksum-pinned Gitleaks. The local pre-commit hook scans
the working tree; CI scans the tree and complete fetched Git history. Ignored
local credentials are never an acceptable configuration mechanism for this app:
enter keys in the settings window and store them in Keychain instead.

## Manual verification

Accessibility and cross-application integration require a logged-in macOS desktop.
Use synthetic, non-sensitive text and verify each acceptance check in
`REQUIREMENTS.md`. Never include source text, keys, or translations in screenshots,
issues, logs, or test artifacts. Live API checks are separate from mocked CI tests.
