# Changelog

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
- Untrusted text (Jira summary, issue titles, commit messages) never goes into a command line. A double-quoted `$0` or backtick in a summary used to expand and could run commands. The skill now writes the title to a file and passes `--title "$(cat <file>)"`; `tests/title-file.test.sh` proves the pattern with a fake `gh`. `gather.sh` refuses branch and base names outside ASCII letters, digits and `._/@+#%,:=~-` or starting with `#` (a shell comment) or `-` (a flag), the command examples single-quote branch and base values, labels and reviewer handles come from files (`"$(cat <file>)"`, so `won't fix` or `$(...)` stay literal), and `linked_issues` no longer matches `fix #12abc`.
- Files are written with the agent's file-writing tool. A heredoc is only a fallback, with a random delimiter checked against the content: a fixed delimiter could end early on preserved text and run the rest as commands.
- Fork PRs: `gather.sh` resolves the base repository (the PR URL, or the parent of a forked `origin`) and fetches the base from a remote that points at it, or by URL, into `refs/autopr/base`. A stale fork branch no longer shapes the diff. It reports `base_repo`, `base_repo_source`, `head_repo` and `base_remote`. With no open PR, the target comes from `--repo`, then `gh repo set-default`, then whatever `gh` resolves (the parent of a forked `origin`, or the `upstream` remote); anything that differs from the `origin` URL's repository is only a guess (`needs-confirmation`), so the skill stops and asks before it targets it. `head_repo` always comes from the `origin` URL, and `--repo` values must be real owner/name pairs (one slash, no leading `-` or `.`). The preview always shows both repositories. The skill adds `--repo` and `--head owner:branch` for fork PRs and updates through `repos/<base_repo>`.
- No `gh` command relies on gh's own repository resolution (with an `upstream` remote, gh picks it over `origin`, so a PR could open on the parent). `gather.sh` names every repository: `gh repo view <head_repo>`, and `gh pr list --repo <candidate> --head <branch>` for each candidate: `--repo` when given, otherwise the origin repository, its parent and the repository of every other remote. It filters by the head owner, because `gh pr list --head` cannot take `owner:branch` and `gh pr view <branch>` can return another fork's PR. Every `gh pr`, `gh issue` and `gh api` command in the skill names its repository (`--repo '<base_repo>'`, `repos/<base_repo>/...`), and a docs lint enforces it. Only `gh repo set-default --view` has no `--repo` flag.
- Publication guard: `gather.sh` fetches the head branch and reports `head_in_sync`, `head_status` and `remote_head`. The skill stops, unless `--dry-run`, when the remote branch is deleted, ahead, force-updated or behind, when HEAD was reset to an ancestor, or when the PR's head commit differs. Before, a stale local tracking ref could pass. A deleted remote branch is detected with `git ls-remote`, not by reading git's English error text.
- The skill writes the body file and creates the PR in separate commands, and checks the file first. A missing heredoc terminator once published command text as the PR body.
- `gather.sh` exits 2 with a message when `gh pr view` fails (other than "no pull requests found") or `git fetch` fails, instead of returning stale data. The skill always runs `gather.sh`, `gh` and `acli` outside the sandbox.
- `gather.sh` reports `pr_lookup` (`found`, `none`, `skipped`). The skill stops, unless `--dry-run`, when the lookup was skipped, so a skipped lookup never leads to a duplicate PR.
- `gather.sh` handles large diffs (the stat no longer dies with SIGPIPE), shallow and single-branch clones, a missing `origin`, non-ASCII paths, and an upstream that names another branch (`git checkout -b feat origin/main`) or another remote (`fork/feat`).
- Body, title and Jira data live in one `mktemp -d` work directory, so parallel runs and sandbox TMPDIR differences cannot collide.
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
