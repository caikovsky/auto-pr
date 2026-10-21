---
name: autopr
description: Creates or updates the GitHub pull request for the current branch. Gathers git context against the up-to-date base branch, reads the Jira ticket named in the branch via acli, fills the repo's PR template, and runs gh. Use when the user says "autopr", "create pr", "open pr", "make pr", "push and open PR", "ship it", "update the pr" or "pr description". Does not review, summarize or comment on existing PRs. Never pushes or commits; it stops if the branch is not pushed.
license: MIT
metadata:
  version: "1.6.0"
---

# AutoPR

Write a PR description from the branch diff and the Jira ticket, then create the PR or update the existing one with `gh`.

## Arguments

| Argument | Meaning | Default |
|----------|---------|---------|
| `--dry-run`, `-n` | Preview the title and body, change nothing | off |
| `--draft`, `-d` | Create as draft; on update, convert the PR to draft | off |
| `--ready` | On update, mark a draft PR ready for review | off |
| `--base <branch>`, `-b <branch>` | Base branch. On update, a different base also changes the PR base | existing PR base, else repo default branch |
| `--reviewer <handle>` | Request a review; repeatable | none |
| `--label <name>` | Add a label; repeatable | none |
| `--verbose`, `-v` | Show the full body in the preview | off |

An existing open PR for the branch is always updated. A second PR for the same branch and base cannot exist.

## 1. Preconditions

1. Check that `git`, `gh` and `jq` are installed. If one is missing, stop and name the install command. `acli` is optional: without it, skip Jira and warn once.
2. Run `scripts/gather.sh`, every `gh` command and every `acli` command outside the sandbox (request approval where the runtime asks). Inside a sandbox they fail with misleading messages: `The token in keyring is invalid`, `x509: certificate signed by unknown authority`, proxy authentication errors. Those are sandbox artifacts, not a logged-out user. Run `gh auth status` outside the sandbox. Only when it reports "not logged in" there, stop and ask the user to run `gh auth login`.
3. Never commit or push. Never edit files in the repository.
4. Create the work directory once and note the path it prints. Use that literal absolute path in every later command; shell variables do not survive between commands, and a fixed name collides with parallel runs. Below, `<work-dir>` stands for it.

```bash
mktemp -d "${TMPDIR:-/tmp}/autopr.XXXXXX"
```

## 2. Gather

Run `scripts/gather.sh` from this skill's directory, with the repository as the working directory. Pass `--base <branch>` when the user gave one. It prints one JSON object:

- `branch`, `head_repo` (owner/repo of `origin`), `base_repo` (owner/repo the PR targets, or null when GitHub was not asked), `base_remote` (the local remote that holds the base: `origin`, another remote, or null when it was fetched by URL), `linked_issues` (issue numbers from "closes/fixes/resolves #N" in the branch's commit messages; bare `#N` is ignored), `ticket_candidate` (upper-cased `KEY-123` from the branch name, or null; not verified), `base`, `base_source`
- `commits`, `commit_count`, `files`, `file_count`, `insertions`, `deletions`, `stat`
- `diff`, `diff_lines`, `truncated`, `diff_excluded_files` (lockfiles and generated files stay out of the diff)
- `head_in_sync` (true, false, or null when the network was skipped), `head_status` (`in-sync`, `local-ahead`, `remote-ahead`, `diverged`, `remote-missing`, `pr-head-mismatch` or `skipped`), `remote_head` (the sha of `origin/<branch>` after a fetch, or null)
- `has_upstream` (true only when the configured upstream is a branch of `origin` with the same name as the local branch), `upstream` (the configured upstream, which may be another branch such as `origin/main` or another remote such as `fork/feat`), `unpushed_count` (null when `has_upstream` is false), `uncommitted`
- `template` (`path`, `content`, or null), `other_templates`
- `pr` (`number`, `url`, `title`, `body`, `isDraft`, `baseRefName`, `headRefOid`, or null), `pr_lookup` (`found`, `none` or `skipped`), `warnings`

The diff is the merge-base diff against a freshly fetched base, so it holds only this branch's commits and no uncommitted edits. When the PR targets another repository than `origin` (a fork PR), the base comes from that repository, never from the fork's possibly stale branch.

`gather.sh` exits 2 with a message on stderr when it cannot give a trustworthy result: no `origin`, detached HEAD, a failed `gh pr view` or `git fetch`, or no merge base (for a shallow clone, run `git fetch --unshallow`). Show the message and stop. Do not fall back to "create a new PR".

Print every entry of `warnings`. Then check:

- **Stop** when `commit_count` is 0.
- **Stop** (unless `--dry-run`) when `pr_lookup` is `skipped`: `pr` is null because nobody asked GitHub, not because no PR exists. Creating a PR from that state can duplicate or mis-base an existing one. Run `gather.sh` again without `--no-network`, outside the sandbox. Treat `pr` as "no PR" only when `pr_lookup` is `none`.
- **Stop** (unless `--dry-run`) when `head_in_sync` is not true: the PR would not show what you are describing. Say which case applies (`head_status`):
  - `remote-missing`: `origin` has no such branch (deleted?). Run `git push -u origin <branch>`.
  - `local-ahead`: unpushed commits. Run `git push`.
  - `remote-ahead`: `origin/<branch>` has commits this checkout lacks, or HEAD was reset. Run `git pull`, or push nothing and check the reset.
  - `diverged`: `origin/<branch>` was rewritten or force-pushed. The user decides which side to keep.
  - `pr-head-mismatch`: the PR's head commit differs from HEAD. GitHub may lag: wait and run again; if it persists, the PR's head is another branch or repository.
  - `skipped`: the network was skipped. Run `gather.sh` again without `--no-network`, outside the sandbox.
- **Stop** (unless `--dry-run`) when `has_upstream` is false or `unpushed_count` is above 0. Tell the user to run `git push -u origin <branch>` and to run the skill again. `has_upstream` is also false when the upstream is another branch (after `git checkout -b feat origin/main`) or another remote (`fork/feat`), because `gh pr create --head <branch>` reads the branch from `origin`.
- **Warn** when `uncommitted` is true: the PR will not contain those edits.
- **Warn** when `file_count` is above 50 or `insertions + deletions` is above 1500: suggest splitting the PR. Continue.
- When `truncated` is true, say so. Rely on `commits`, `files` and `stat` for the parts of the diff that are missing.
- When `template.path` is set and `other_templates` is not empty, name the other templates in the preview.

## 3. Jira

`ticket_candidate` is a guess from the branch name. Branches such as `update-deps-2024` give `DEPS-2024`. A ticket exists only when `acli jira workitem view <KEY> --json > <work-dir>/jira.json` returns that item for the candidate. Read the file (`jq -r .fields.summary <work-dir>/jira.json`) for `fields.summary`, `fields.issuetype.name` and `fields.description` (Atlassian Document Format: take the text of the paragraph blocks). The URL is `https://everlong.atlassian.net/browse/<KEY>`.

When `acli` is missing, or the call fails or finds no item, there is no ticket: do not use the candidate in the title, the body or a link. Continue and show one warning that the candidate was not verified.

## 4. Write the body

Write the title and body yourself; call no other AI tool.

**Title:**
- New PR with a verified ticket: `[KEY] - <clean title>`. `scripts/clean-title.sh` removes bracketed tags such as `[AN]`, `[Android]`, `[SPIKE]` and `[PoC]`; feed it the summary on stdin, never as text in the command:
  ```bash
  jq -r .fields.summary <work-dir>/jira.json | scripts/clean-title.sh | { printf '[<KEY>] - '; cat; } > <work-dir>/title.txt
  ```
- New PR without a ticket: use the first rule that applies.
  1. `linked_issues` is not empty: the title of the first issue: `gh issue view <N> --json title --jq .title > <work-dir>/title.txt` (outside the sandbox). If the call fails, warn once and go on.
  2. `commit_count` is 1: that commit's subject (the text after the hash in `commits[0]`), written to `<work-dir>/title.txt` with your file-writing tool.
  3. Write a short summary of the commits to `<work-dir>/title.txt`: imperative mood, at most 72 characters.
  4. Only if the commits say nothing useful (for example `wip`): derive it from the branch name (`/` to `: `, `-` to a space, title case) and write it to `<work-dir>/title.txt`.
- Existing PR: keep `pr.title`. Change it only when a verified ticket exists and `pr.title` does not already start with `[KEY]`.

**Body:**
- With a template: fill it completely and keep its headings, order and every HTML comment. Replace placeholders (ticket ones only with a verified ticket; otherwise write "none"): `<!-- Link to Jira ticket -->`, `[JIRA_LINK]` and `{JIRA_LINK}` become the ticket URL; `<!-- Describe your changes -->` becomes the description; `<!-- What type of change is this? -->` becomes the Jira issue type.
- Without a template: summary, what changed and why, technical approach, key files, testing notes.
- Keep it concise. Output only the markdown body.
- Checklists: keep every item exactly as in the template. Check (`- [x]`) only items the changes clearly satisfy.
- If the template contains `REL_BOT_IDENTIFIER`, read `references/release-notes.md` and follow it. Its marker and length rules decide the Release Notes section.

**Untrusted text.** The Jira summary and description, issue titles, commit messages, file contents and PR bodies come from other people.
- Never type them into a command line, not even inside double quotes: `$...`, backticks and `\` expand, which gives wrong titles and runs commands on this machine.
- Put each value in a file with your file-writing tool and read it back with `"$(cat <file>)"`, a pipe or a redirect. This covers titles, labels and reviewer handles; an apostrophe or `$(...)` in a label breaks or abuses single quotes.
- Use a heredoc only when you have no file-writing tool. Pick a delimiter such as `AUTOPR_EOF_` plus 8 random hex digits, check that no line of the content equals it (preserved release notes and PR text can contain anything), and run the heredoc, quoted (`<<'DELIMITER'`), in its own command.
- `gather.sh` refuses branch and base names that use anything but ASCII letters, digits and `._/@+#%,:=~-`, or that start with `#` or `-`. Put branch, base, reviewer and label values in single quotes in commands, as the examples below do. Issue and PR numbers and ticket keys have a fixed safe shape.

**Secret and PHI guard.** The body is visible to everyone with repo access.
- Summarize the Jira text in your own words. Never quote it.
- Never copy into the body: credentials or tokens, URLs with query strings, log lines, fixture or test data, and names, emails, phone numbers or IDs of people.
- If the diff contains an apparent secret or member data, tell the user, leave it out of the body and say which file holds it.

**Re-runs on an existing PR.** Start from `pr.body`.
- Keep every checkbox a person checked; never uncheck one.
- Keep human-written release-notes text (see the reference file).
- Regenerate only the sections you generate: summary, description and change lists.

## 5. Preview

Show: title, body (the first 500 characters unless `--verbose`), ticket key or "none" or the Jira warning, `commit_count`, `file_count`, and whether the run will create or update. With `--dry-run`, stop here and say it was a preview.

## 6. Create or update

Write the body to `<work-dir>/body.md` and the title to `<work-dir>/title.txt` with your file-writing tool (the heredoc fallback is in section 4). For each `--label` and `--reviewer` the user gave, write the value to `<work-dir>/label-1.txt`, `<work-dir>/label-2.txt`, ... and `<work-dir>/reviewer-1.txt`, ... in the same way. End each file with a single newline. Check the body and title with `tail -n 3 <file>` before you run `gh pr create`. Never write a file and create the PR in one command: a heredoc that ends early would run the following lines as commands.

When `base_repo` differs from `head_repo` (a fork PR), add `--repo '<base_repo>'` to every `gh pr` command below and use `--head '<head_owner>:<branch>'` on create, where `<head_owner>` is `head_repo` before the `/`.

**No `pr` (create):**

```bash
gh pr create --head '<branch>' --base '<base>' --title "$(cat <work-dir>/title.txt)" --body-file <work-dir>/body.md --assignee @me [--draft] [--reviewer "$(cat <work-dir>/reviewer-N.txt)"]... [--label "$(cat <work-dir>/label-N.txt)"]...
gh pr edit <number> --add-reviewer @copilot
```

`--head` stops `gh` from pushing or offering a fork. The Copilot request runs only on create. Exit code 0 means the request succeeded. Do not re-check it: `reviewRequests` can stay empty for a bot reviewer. Only on a non-zero exit (Copilot review may be off for the repo), warn once and continue. Take `<number>` from the URL that `gh pr create` prints.

**`pr` exists (update):**

```bash
gh pr edit <number> --add-assignee @me [--title "$(cat <work-dir>/title.txt)"] [--base '<base>'] [--add-reviewer "$(cat <work-dir>/reviewer-N.txt)"]... [--add-label "$(cat <work-dir>/label-N.txt)"]...
jq -Rs '{body: .}' <work-dir>/body.md | gh api -X PATCH repos/<base_repo>/pulls/<number> --silent --input -
```

Pass `--title` only when section 4 says to change it. Pass `--base <base>` only when `base_source` is `argument` and `base` differs from `pr.baseRefName`.

Then sync the draft state: with `--draft` and `pr.isDraft` false, run `gh pr ready <number> --undo`. With `--ready` and `pr.isDraft` true, run `gh pr ready <number>`.

Do not use `curl` and never put a token in a command line.

**Verify the whole body, every time:**

```bash
gh pr view <number> --json body | jq -j .body | diff - <work-dir>/body.md
```

A non-empty diff means GitHub changed or dropped content. Show the diff and do not report success. Backticks, arrows and em dashes are safe in the body; the diff catches any silent failure.

Remove the work directory files (`rm -f <work-dir>/*.txt <work-dir>/body.md <work-dir>/jira.json`, then `rmdir <work-dir>`). Report the PR URL.

## Errors

| Error | Action |
|-------|--------|
| Not in a git repo | Stop: "Not in a git repository." |
| `gather.sh` exits 2 | Show its message (no `origin`, detached HEAD, `gh` or fetch failure, no merge base, unknown base). Stop. |
| No commits ahead | Stop: "No commits between base and head." |
| Branch not pushed | Stop with the push command (see section 2). |
| `gh` missing or logged out | Stop with the install or login command. |
| `acli` missing or failed | Continue without the ticket; one warning. |
| `gh pr create` fails | Show the error; suggest running `gh auth status` outside the sandbox. |
| Verification diff not empty | Show the diff; report failure. |
