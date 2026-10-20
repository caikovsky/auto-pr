# Changelog

## 1.6.0

- PR titles drop bracketed tags from the Jira summary (`[AN]`, `[Android]`, `[iOS]`, `[SPIKE]`, `[PoC]`, in any position). `scripts/clean-title.sh` does it; the rules come from the former Python CLI (issue #5, CLI change #7). A summary that is only tags keeps its original text.

## 1.5.0

Fixes from a review of the skill. Behavior changes are marked **breaking**.

- **Breaking:** removed the optional chat post that requested a review, with its argument and its phase.
- **Breaking:** removed `--new` and `--update`. An open PR for the branch is always updated, because GitHub allows one open PR per head and base.
- Diff base is now `origin/<base>...HEAD` after a fetch. Before, it was the working tree against the local base tip, which showed uncommitted edits and, when the base had moved, upstream commits as reverts.
- The base branch is resolved from `--base`, then the existing PR, then the repo default branch, then `origin/HEAD`, then the first of `main`, `master` and `develop` found on `origin`. It is no longer fixed to `main`. On update, a `--base` that differs from the PR base also changes the PR base.
- Added `scripts/gather.sh`: one JSON object with branch, ticket candidate, base, commits, files, truncated diff (lockfiles and generated files excluded), upstream status, uncommitted flag, PR template and existing PR. This replaces four subagents.
- The skill stops when the branch has no upstream or has unpushed commits, and passes `--head` to `gh pr create`, so `gh` never pushes or offers a fork.
- Existing PRs are found with `gh pr view`, which also works for fork PRs.
- Ticket keys match case-insensitively (`feature/tlab-2023-x`) and may contain digits. The key is a candidate (`ticket_candidate`): the skill uses it only when `acli` returns the item, so branches such as `update-deps-2024` do not produce a fake ticket. Keys need two leading letters and do not match version numbers like `lodash-4.17.21`.
- PR updates use `jq` and `gh api --silent --input`: no `curl`, no token in the command line, and a failed request returns an error. The check after an update diffs the whole body.
- On update, the skill keeps the human-written PR title unless a verified ticket exists.
- A new PR without a ticket takes its title from the linked issue (`gather.sh` reports `linked_issues` from "closes/fixes/resolves #N" in the commits), else the subject of a single commit, else a short summary of the commits, and only last from the branch name.
- The Copilot request counts as done on exit code 0 (`reviewRequests` can stay empty for a bot reviewer); the skill warns only on a non-zero exit.
- The skill writes the body file and creates the PR in separate commands, and checks the file first. A missing heredoc terminator once published command text as the PR body.
- `gather.sh` exits 2 with a message when `gh pr view` fails (other than "no pull requests found") or `git fetch` fails, instead of returning stale data. The skill always runs `gather.sh`, `gh` and `acli` outside the sandbox.
- `gather.sh` reports `pr_lookup` (`found`, `none`, `skipped`). The skill stops, unless `--dry-run`, when the lookup was skipped, so a skipped lookup never leads to a duplicate PR.
- `gather.sh` handles large diffs (the stat no longer dies with SIGPIPE), shallow and single-branch clones, a missing `origin`, non-ASCII paths, and an upstream that names another branch (`git checkout -b feat origin/main`) or another remote (`fork/feat`).
- The body file comes from `mktemp`, so parallel runs and sandbox TMPDIR differences cannot collide.
- Copilot review is requested on create only, with `gh pr edit --add-reviewer @copilot`.
- Draft state syncs on update (`gh pr ready`, `--ready`). Added `--reviewer` and `--label`.
- Warning above 50 files or 1500 changed lines.
- Re-runs keep checked boxes and human-written release notes.
- Added a secret and PHI guard for the PR body.
- Removed the subagent cache cleanup phase (it ran `rm -f` on transcript files).
- Removed the sandbox settings check, which read the wrong settings paths. The skill now runs `gh auth status` and retries outside the sandbox on a sandbox error.
- Removed the backtick, arrow and em dash ban. A test on a PR showed `gh pr edit --body-file` stores them unchanged. Updates still go through `gh api --input`, and the full-body diff catches any silent change.
- The skill text is agent-neutral (Claude Code and Codex).
- Release notes and CI marker rules moved to `references/release-notes.md`, loaded only for templates that contain `REL_BOT_IDENTIFIER`. Marker and length rules no longer contradict each other.
- Frontmatter description: dropped "AI-powered" and "Use ALWAYS", added the triggers "push and open PR" and "ship it", and stated that the skill does not review or summarize PRs.
- Added `tests/gather.test.sh`, a CI workflow (Linux, plus macOS with the system bash 3.2; actions pinned by SHA, tool versions pinned) and `agents/openai.yaml` for Codex display metadata.

## 1.4.1

Baseline: the skill as migrated from the Python CLI repo.
