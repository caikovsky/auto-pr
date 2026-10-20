# Changelog

## 1.5.0

Fixes from a review of the skill. Behavior changes are marked **breaking**.

- **Breaking:** removed the Slack review request (`--slack`, Phase 6).
- **Breaking:** removed `--new` and `--update`. An open PR for the branch is always updated, because GitHub allows one open PR per head and base.
- Diff base is now `origin/<base>...HEAD` after a fetch. Before, it was the working tree against the local base tip, which showed uncommitted edits and, when the base had moved, upstream commits as reverts.
- The base branch is resolved from `--base`, then the existing PR, then the repo default branch, then `origin/HEAD`. It is no longer fixed to `main`.
- Added `scripts/gather.sh`: one JSON object with branch, ticket, base, commits, files, truncated diff (lockfiles and generated files excluded), upstream status, uncommitted flag, PR template and existing PR. This replaces four subagents.
- The skill stops when the branch has no upstream or has unpushed commits, and passes `--head` to `gh pr create`, so `gh` never pushes or offers a fork.
- Existing PRs are found with `gh pr view`, which also works for fork PRs.
- Ticket keys match case-insensitively (`feature/tlab-2023-x`) and may contain digits.
- PR updates use `jq` and `gh api --input`: no `curl`, no token in the command line, and errors are visible. The check after an update diffs the whole body.
- Copilot review is requested on create only, with `gh pr edit --add-reviewer @copilot`.
- Draft state syncs on update (`gh pr ready`, `--ready`). Added `--reviewer` and `--label`.
- Warning above 50 files or 1500 changed lines.
- Re-runs keep checked boxes and human-written release notes.
- Added a secret and PHI guard for the PR body.
- Removed the subagent cache cleanup phase (it ran `rm -f` on transcript files).
- Removed the sandbox settings check, which read the wrong settings paths. The skill now runs `gh auth status` and retries outside the sandbox on a sandbox error.
- Removed the backtick, arrow and em dash ban. A test on a PR showed `gh pr edit --body-file` stores them unchanged.
- The skill text is agent-neutral (Claude Code and Codex).
- Release notes and CI marker rules moved to `references/release-notes.md`, loaded only for templates that contain `REL_BOT_IDENTIFIER`. Marker and length rules no longer contradict each other.
- Frontmatter description: dropped "AI-powered" and "Use ALWAYS", added the triggers "push and open PR" and "ship it", and stated that the skill does not review or summarize PRs.
- Added `tests/gather.test.sh`, a CI workflow, and `agents/openai.yaml` for Codex display metadata.

## 1.4.1

Baseline: the skill as migrated from the Python CLI repo.
