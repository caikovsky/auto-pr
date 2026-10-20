---
name: autopr
description: Creates or updates the GitHub pull request for the current branch. Gathers git context against the up-to-date base branch, reads the Jira ticket named in the branch via acli, fills the repo's PR template, and runs gh. Use when the user says "autopr", "create pr", "open pr", "make pr", "push and open PR", "ship it", "update the pr" or "pr description". Does not review, summarize or comment on existing PRs. Never pushes or commits; it stops if the branch is not pushed.
license: MIT
metadata:
  version: "1.5.0"
---

# AutoPR

Write a PR description from the branch diff and the Jira ticket, then create the PR or update the existing one with `gh`.

## Arguments

| Argument | Meaning | Default |
|----------|---------|---------|
| `--dry-run`, `-n` | Preview the title and body, change nothing | off |
| `--draft`, `-d` | Create as draft; on update, convert the PR to draft | off |
| `--ready` | On update, mark a draft PR ready for review | off |
| `--base <branch>`, `-b <branch>` | Base branch | existing PR base, else repo default branch |
| `--reviewer <handle>` | Request a review; repeatable | none |
| `--label <name>` | Add a label; repeatable | none |
| `--verbose`, `-v` | Show the full body in the preview | off |

An existing open PR for the branch is always updated. A second PR for the same branch and base cannot exist.

## 1. Preconditions

1. Check that `git`, `gh` and `jq` are installed. If one is missing, stop and name the install command. `acli` is optional: without it, skip Jira and warn once.
2. Run `gh auth status`. If it reports an error caused by the sandbox (permission or network denied), retry the command outside the sandbox. If it reports "not logged in", stop and ask the user to run `gh auth login`.
3. Never commit or push. Never edit files in the repository.

## 2. Gather

Run `scripts/gather.sh` from this skill's directory, with the repository as the working directory. Pass `--base <branch>` when the user gave one. It prints one JSON object:

- `branch`, `ticket` (upper-cased key or null), `base`, `base_source`
- `commits`, `commit_count`, `files`, `file_count`, `insertions`, `deletions`, `stat`
- `diff`, `diff_lines`, `truncated`, `diff_excluded_files` (lockfiles and generated files stay out of the diff)
- `has_upstream`, `unpushed_count`, `uncommitted`
- `template` (`path`, `content`, or null), `other_templates`
- `pr` (`number`, `url`, `title`, `body`, `isDraft`, `baseRefName`, or null), `warnings`

The diff is `origin/<base>...HEAD` after a fetch, so it holds only this branch's commits and no uncommitted edits.

Print every entry of `warnings`. Then check:

- **Stop** when `commit_count` is 0.
- **Stop** (unless `--dry-run`) when `has_upstream` is false or `unpushed_count` is above 0. Tell the user to run `git push -u origin <branch>` (or `git push`) and to run the skill again.
- **Warn** when `uncommitted` is true: the PR will not contain those edits.
- **Warn** when `file_count` is above 50 or `insertions + deletions` is above 1500: suggest splitting the PR. Continue.
- When `truncated` is true, say so. Rely on `commits`, `files` and `stat` for the parts of the diff that are missing.
- When `template.path` is set and `other_templates` is not empty, name the other templates in the preview.

## 3. Jira

When `ticket` is set and `acli` exists, run `acli jira workitem view <KEY> --json`. Read `fields.summary`, `fields.issuetype.name` and `fields.description` (Atlassian Document Format: take the text of the paragraph blocks). The URL is `https://everlong.atlassian.net/browse/<KEY>`.

When `acli` is missing or the call fails, continue without ticket data and show one warning.

## 4. Write the body

Write the title and body yourself; call no other AI tool.

**Title:**
- With a ticket: `[KEY] - Clean Ticket Title`. Remove bracketed tags such as `[AN]` or `[SPIKE]` from the ticket title.
- Without a ticket: derive it from the branch name (`/` to `: `, `-` to a space, title case).

**Body:**
- With a template: fill it completely and keep its headings, order and every HTML comment. Replace placeholders: `<!-- Link to Jira ticket -->`, `[JIRA_LINK]` and `{JIRA_LINK}` become the ticket URL; `<!-- Describe your changes -->` becomes the description; `<!-- What type of change is this? -->` becomes the Jira issue type.
- Without a template: summary, what changed and why, technical approach, key files, testing notes.
- Keep it concise. Output only the markdown body.
- Checklists: keep every item exactly as in the template. Check (`- [x]`) only items the changes clearly satisfy.
- If the template contains `REL_BOT_IDENTIFIER`, read `references/release-notes.md` and follow it. Its marker and length rules decide the Release Notes section.

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

Write the body to `"$TMPDIR/autopr-body.md"` with a quoted heredoc (`<<'AUTOPR_EOF'`) so the shell does not expand anything. End the file with a single newline.

**No `pr` (create):**

```bash
gh pr create --head <branch> --base <base> --title "<title>" --body-file "$TMPDIR/autopr-body.md" --assignee @me [--draft] [--reviewer <handle>]... [--label <name>]...
gh pr edit <number> --add-reviewer @copilot
```

`--head` stops `gh` from pushing or offering a fork. The Copilot request runs only on create. If it fails (Copilot review may be off for the repo), warn once and continue. Take `<number>` from the URL that `gh pr create` prints.

**`pr` exists (update):**

```bash
gh pr edit <number> --title "<title>" --add-assignee @me [--add-reviewer <handle>]... [--add-label <name>]...
jq -Rs '{body: .}' "$TMPDIR/autopr-body.md" | gh api -X PATCH repos/{owner}/{repo}/pulls/<number> --input -
```

Then sync the draft state: with `--draft` and `pr.isDraft` false, run `gh pr ready <number> --undo`. With `--ready` and `pr.isDraft` true, run `gh pr ready <number>`.

Do not use `curl` and never put a token in a command line.

**Verify the whole body, every time:**

```bash
gh pr view <number> --json body | jq -j .body | diff - "$TMPDIR/autopr-body.md"
```

A non-empty diff means GitHub changed or dropped content. Show the diff and do not report success. Backticks, arrows and em dashes are safe in the body; the diff catches any silent failure.

Report the PR URL.

## Errors

| Error | Action |
|-------|--------|
| Not in a git repo | Stop: "Not in a git repository." |
| `gather.sh` exits 2 | Show its message (detached HEAD, no `origin`, unknown base). Stop. |
| No commits ahead | Stop: "No commits between base and head." |
| Branch not pushed | Stop with the push command (see section 2). |
| `gh` missing or logged out | Stop with the install or login command. |
| `acli` missing or failed | Continue without the ticket; one warning. |
| `gh pr create` fails | Show the error; suggest `gh auth status`. |
| Verification diff not empty | Show the diff; report failure. |
