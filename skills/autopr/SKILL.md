---
name: autopr
description: AI-powered PR creation tool. Gathers git context, fetches Jira ticket from branch name via acli, finds PR templates, generates a professional PR description, creates/updates the PR via gh CLI, and can post a review request to Slack channel C0AUU2B9D54 when explicitly requested. Use ALWAYS when the user asks to create/update a pull request, including phrases like "autopr", "create pr", "generate pr", "make pr", "open pr", "pr description", or any request to open or update a PR.
license: MIT
metadata:
  version: "1.4.1"
---

# AutoPR - AI-Powered Pull Request Creator

Generate and create GitHub Pull Requests with AI-powered descriptions using git context and Jira ticket information.

## Phase 0: Environment Setup & Preconditions

Before doing anything else, verify the environment is ready. Run all checks in parallel where possible.

### 0.1 Required CLI Tools

Check that `git`, `gh`, and `acli` are installed:

```bash
which git && which gh && which acli
```

**If `git` is missing:** Stop. Tell the user: "git is required. Install via `xcode-select --install` or `brew install git`."

**If `gh` is missing:** Stop. Tell the user:
- macOS: `brew install gh`
- Other: https://cli.github.com/
- After install: `gh auth login -h github.com`

**If `acli` is missing:** Warn (not fatal): "acli (Atlassian CLI) is not installed. Jira ticket enrichment will be skipped. To install: `brew tap atlassian/atlassian && brew install atlassian-cli`" -- then continue without ticket info.

### 0.2 Authentication Check

```bash
gh auth status 2>&1
```

If authentication is invalid/expired, guide the user:
1. "Your `gh` authentication is invalid. Run: `! gh auth logout -h github.com && gh auth login -h github.com`"
2. Wait for the user to confirm, then re-verify with `gh auth status`.
3. Do NOT proceed until auth is confirmed working.

### 0.3 Sandbox Permissions

Check that `gh` and `acli` commands are excluded from the Codex sandbox. Read the project's `.Codex/settings.local.json` (or user's `~/.Codex/settings.json`) and verify that `sandbox.excludedCommands` includes `"gh *"` and `"acli *"`.

**If `gh *` is NOT in `excludedCommands`:** Tell the user:
> `gh` commands are sandboxed and will be blocked. Add `"gh *"` to your sandbox exclusions.
> You can do this by adding to `.Codex/settings.local.json` or `~/.Codex/settings.json`:
> ```json
> "sandbox": { "excludedCommands": ["gh *"] }
> ```

**If `acli *` is NOT in `excludedCommands`** (and acli is installed): Same guidance for `"acli *"`.

Only proceed to Phase 1 once all checks pass.

### 0.4 Repository Check

- Must be inside a git repository with commits ahead of the base branch.

### 0.5 Subagent Cache Cleanup

Codex caches subagent metadata and may fuzzy-match stale agents from previous runs. Clear any cached subagents from prior autopr sessions to prevent context contamination:

```bash
# Find and remove stale autopr-related subagent caches for this project
PROJ_DIR=$(find ~/.Codex/projects -maxdepth 2 -type d -name "subagents" 2>/dev/null | head -5)
for dir in $PROJ_DIR; do
  # Remove agents whose metadata mentions "Jira ticket" or "git context" or "PR template" or "existing PR" (autopr subagents)
  grep -rl '"description".*\(Jira ticket\|git context\|PR template\|existing PR\|Collect git\|Check existing\|Find PR\|Fetch Jira\)' "$dir"/*.meta.json 2>/dev/null | while read f; do
    base="${f%.meta.json}"
    rm -f "$base".meta.json "$base".jsonl
  done
done
```

This prevents stale ticket context from a previous branch bleeding into the current run.

## Arguments

Parse the user's arguments to determine mode and options:

| Argument | Meaning | Default |
|----------|---------|---------|
| `--dry-run` or `-n` | Preview without creating PR | false |
| `--draft` or `-d` | Create as draft PR | false |
| `--base <branch>` or `-b <branch>` | Base branch for PR | `main` |
| `--update` or `-u` | Update existing PR (skip prompt) | false |
| `--new` | Create new PR (skip prompt) | false |
| `--verbose` or `-v` | Show full PR description | false |
| `--slack` | Post a Slack review request after success | false |
| (no args) | Normal interactive mode | - |

### Phase 1: Parallel Data Gathering (4 subagents)

First, get the current branch name (needed by subagents):
```bash
git branch --show-current
```
Validate branch is not empty. Extract Jira ticket key using pattern `[A-Z]+-\d+` (e.g., `task/TLAB-2023` -> `TLAB-2023`).

Then launch subagents **in parallel** using the Agent tool in a single message. All are independent and need no shared state.

**Model routing:** These subagents only run shell commands and return output. Use `model="haiku"` for all of them to minimize token cost. The expensive reasoning (PR description generation) happens in Phase 3 on the main orchestrator.

#### Subagent 1: Git Context Collector
```
Agent(model="haiku", description="Collect git context")
```
Prompt: Run these git commands and return ALL outputs as structured text. Do NOT analyze or summarize - just return the raw output:
- `git log <base>..HEAD --oneline --no-decorate` (commit messages)
- `git diff --name-only <base>` (changed files)
- `git diff --stat <base>` (diff stats)
- `git diff <base> --no-color` (full diff - if output exceeds 800 lines, return only the first 800 lines and note the truncation)

Return: commit list, changed files list, diff stat, diff content, commit count, file count.

#### Subagent 2: Jira Ticket Fetcher
```
Agent(model="haiku", description="Fetch Jira ticket")
```
Prompt: Fetch Jira ticket `<TICKET_KEY>` using acli. Do NOT analyze - just return the parsed fields:
- First check if `acli` is available: `which acli`
- If available: `acli jira workitem view <TICKET_KEY> --json`
- Parse JSON to extract: key, fields.summary (title), fields.description (may be Atlassian Document Format - extract text from paragraph content blocks), fields.issuetype.name, and construct URL: `https://everlong.atlassian.net/browse/<KEY>`
- If acli not found or fails, return a warning message instead of erroring

**Skip this subagent entirely if no ticket key was extracted from the branch name.** In that case, ticket is simply N/A - launch only 3 subagents.

#### Subagent 3: PR Template Finder
```
Agent(model="haiku", description="Find PR template")
```
Prompt: Find and return the PR template for this repository. Do NOT summarize - return the full template content:
- Get repo root: `git rev-parse --show-toplevel`
- Check these paths in order and return the content of the first one found:
  1. `.github/pull_request_template.md`
  2. `.github/PULL_REQUEST_TEMPLATE.md`
  3. `pull_request_template.md`
  4. `PULL_REQUEST_TEMPLATE.md`
- If none found, return "no template found"

#### Subagent 4: Existing PR Checker
```
Agent(model="haiku", description="Check existing PR")
```
Prompt: Check if a PR already exists for branch `<current_branch>`. Return the raw result:
```bash
gh pr list --head <current_branch> --json number,title,body,url,isDraft --limit 1
```
Return the PR number, title, URL, and draft status if found. Return "no existing PR" otherwise.

### Phase 2: Collect Results

Wait for all 4 subagents to complete. Gather their results:
- **Git context**: commits, changed files, diff, stats
- **Jira ticket**: ticket details or N/A/warning
- **PR template**: template content or none
- **Existing PR**: PR info or none

### Phase 3: Generate PR Description

Using ALL the context gathered (git diff, commits, changed files, Jira ticket, PR template), generate a professional PR description.

**As Codex, YOU are the AI provider.** Generate the PR description directly - do not call any external AI CLI.

Follow these guidelines when generating:
- If a PR template was found, fill it in completely, keeping its structure and headings
- Replace template placeholders:
  - `<!-- Link to Jira ticket -->` or `[JIRA_LINK]` or `{JIRA_LINK}` -> Jira ticket URL
  - `<!-- Describe your changes -->` -> Description of changes
  - `<!-- What type of change is this? -->` -> Issue type from Jira
- If no template, create a well-structured description with:
  - Summary of changes
  - What was changed and why
  - Technical approach
  - Key files impacted
  - Testing considerations
- Be concise but thorough
- Use professional language
- Output ONLY the PR description in markdown format

#### CRITICAL: GitHub API Body Content Restrictions

The GitHub API silently rejects PR body updates containing certain characters. The PATCH response may return HTTP 200 and even echo back the old body, giving no indication of failure.

**Forbidden characters in PR body content:**
- **Backticks** (`` ` ``) — Do NOT use inline code formatting. Write class/method names as plain text instead.
- **Unicode arrows and special symbols** (`→`, `≠`, `←`, etc.) — Use ASCII equivalents: "to", "is not the same as", "from", etc.
- **Em dashes** (`—`) — Use regular dashes (`-`) instead.

**How this manifests:** `gh pr edit --body-file` and `gh api PATCH` both return success (HTTP 200) but the body remains unchanged. There is NO error message. The only way to detect this is to GET the PR body after the update and compare.

**Safe formatting:** Bold (`**text**`), bullet points (`-`), numbered lists, headings (`##`), links (`[text](url)`), and checkboxes (`- [ ]`, `- [x]`) all work fine.

#### CRITICAL: Release Notes Section (Pipeline-Breaking)

Many repositories have CI pipelines that parse the PR body for **exact HTML comment markers**. If these markers are missing, escaped, or malformed, the pipeline WILL fail.

**Rules for the Release Notes section:**

1. **Use 3-dash HTML comment tags** — The CI bot (`release-notes-check`) parses with `<!---` (3 dashes), NOT `<!--` (2 dashes). The template file may use 2 dashes, but the **output MUST use 3 dashes**:
   - `<!---REL_BOT_IDENTIFIER--->` (not `<!--REL_BOT_IDENTIFIER-->`)
   - `<!---DO_NOT_DELETE--->` (not `<!--DO_NOT_DELETE-->`)

2. **Preserve the exact structure:**
   ```markdown
   ## Release Notes

   <!---REL_BOT_IDENTIFIER--->
   - <your release note here>
   <!---DO_NOT_DELETE--->
   ```

3. **Minimum 80 characters**: The CI bot enforces `${#release_notes} -lt 80`. Each release note line (after stripping `- ` prefix) must be at least **80 characters**. Write descriptive, user-facing notes — not terse one-liners.

4. **Write a concise, user-facing release note** between the two markers. Follow these rules:
   - Write from the user's perspective (what changed for them), not the developer's
   - One bullet point per logical change
   - No internal jargon, class names, or implementation details
   - Follow the [Writing Release Notes Guidelines](https://everlong.atlassian.net/wiki/spaces/REL/pages/5065441305/Writing+release+notes+-+guidelines) if available in the repo

5. **If the template has other HTML comment markers** (e.g., `<!---DO_NOT_DELETE--->`, `<!---rel_bot_tag--->`, or any `<!---...--->` / `<!--...-->`), preserve ALL of them verbatim. These are machine-parsed by CI bots and GitHub Actions.

6. **Checklist sections:** Keep all checkbox items (`- [ ]` and `- [x]`) exactly as they appear in the template. Only check boxes (`- [x]`) that are clearly satisfied by the changes. Leave all others unchecked (`- [ ]`).

7. **When writing the PR body to a temp file for `gh` commands**, ensure HTML comments are NOT escaped. Verify the temp file contains literal `<!---` not `<\!---` or `&lt;!---`.

**PR Title format:**
- With ticket: `[JIRA-KEY] - Ticket Clean Title` (remove bracketed tags like [AN], [SPIKE] from title)
- Without ticket: Derive from branch name (replace `/` with `: `, `-` with spaces, title case)

### Phase 4: Present Results to User

Display to the user:
- PR Title (in a panel/highlight)
- PR Description (full if `--verbose`, truncated to ~500 chars otherwise)
- Ticket info (key, or warning if fetch failed, or "N/A")
- Commit count
- File count

### Phase 5: Create or Update PR

**If `--dry-run`:** Stop here and tell the user this was a preview.

**If existing PR found and not `--new`:**
- If `--update`: Update it directly
- Otherwise: Ask the user: "Found existing PR #N: <title>. [U]pdate existing or create [N]ew?"

**To update an existing PR:**

`gh pr edit --body-file` and `gh api --field` silently fail for bodies with special characters. Use `curl` with JSON input instead:

```bash
# 1. Write body to temp file (use heredoc with 'AUTOPR_EOF' to prevent shell interpolation)
cat > "$TMPDIR/autopr-body.md" << 'AUTOPR_EOF'
<pr description content - NO backticks or unicode>
AUTOPR_EOF

# 2. Update title, assign to author, and request Copilot review (gh edit works reliably for these)
gh pr edit <pr_number> --title "<title>" --add-assignee @me --add-reviewer copilot-pull-request-reviewer
# If the command fails on the reviewer slug, retry without --add-reviewer and warn the user once.
# Do NOT block on Copilot review enrollment.

# 3. Update body via curl + jq (reliable for all content)
TOKEN=$(gh auth token)
jq -Rs '{"body": .}' "$TMPDIR/autopr-body.md" | curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d @- \
  "https://api.github.com/repos/<owner>/<repo>/pulls/<pr_number>" > /dev/null

# 4. ALWAYS verify the update persisted (GitHub silently drops some content)
gh api repos/<owner>/<repo>/pulls/<pr_number> --jq '.body' | head -5
# If verification shows old body, check for backticks/unicode in the content
```

**To create a new PR:**
```bash
gh pr create --title "<title>" --body-file "$TMPDIR/autopr-body.md" --base <base_branch> --assignee @me --reviewer copilot-pull-request-reviewer
```
Add `--draft` flag if `--draft` was specified.

`--assignee @me` assigns the PR to the authenticated `gh` user (the PR author). This must always be included.

`--reviewer copilot-pull-request-reviewer` requests a GitHub Copilot code review. This must always be attempted. If the command fails because the slug is not recognized for the target repo (Copilot Code Review may be disabled at the org/repo level), retry without that flag and surface a one-line warning to the user. Do NOT block PR creation on Copilot review enrollment.

Note: `gh pr create --body-file` works reliably for new PRs. The silent failure only affects updates to existing PRs.

**Post-create/update:** Always verify the body by reading it back with `gh api` or `gh pr view`.

Report the PR URL on success.

### Phase 6: Optional Slack Review Request

Default: do not send a Slack message. Skip this phase without prompting.

Only after a successful create/update, post a review request when the user explicitly asks for a Slack message in the current request or passes `--slack`. A request to create or update a PR alone does not authorize a Slack message. Always skip this phase for `--dry-run`.

**Channel:** `C0AUU2B9D54` (https://league.enterprise.slack.com/archives/C0AUU2B9D54)

Use the `mcp__claude_ai_Slack__slack_send_message` tool with:
- `channel_id`: `C0AUU2B9D54`
- `message`: short review-request text that includes the PR title and URL. Example:

```
:eyes: Review please — <PR title>
<PR URL>
```

If a Jira ticket was found, prefix the title with the key (already done in the PR title). Keep the message brief.

**Failure handling:** If the Slack tool is unavailable or the post fails, surface the error to the user but do NOT roll back the PR. Always report the PR URL regardless of Slack outcome.

## Error Handling

| Error | Action |
|-------|--------|
| Not in a git repo | Stop with message: "Not in a git repository. Run from inside a git repo." |
| No commits ahead of base | Stop with message: "No commits between base and head branch." |
| gh not installed | Stop with install instructions (see Phase 0.1) |
| gh not authenticated | Stop with re-auth guidance (see Phase 0.2) |
| gh/acli not in sandbox exclusions | Stop with settings guidance (see Phase 0.3) |
| acli not found/failed | Continue without Jira ticket, show warning |
| PR creation fails | Show error and suggest checking `gh auth status` |

## Important Notes

- NEVER push code or make commits - this skill only creates/updates PRs
- NEVER modify any files in the repository
- NEVER use backticks, Unicode arrows/symbols, or em dashes in PR body content — GitHub API silently rejects them
- For new PRs, `gh pr create --body-file` works reliably
- For updating existing PRs, always use the `curl` + `jq -Rs` approach documented in Phase 5 — `gh pr edit --body-file` silently fails
- Always verify the body persisted by reading it back after create/update
