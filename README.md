# Auto-PR: Automated Pull Request Creator

A CLI tool that automatically creates GitHub Pull Requests with intelligent content generation. Combines **Jira ticket data** with **git commit history** and **changed files** to auto-fill PR templates.

## Features

- **Extracts Jira ticket** from branch name (e.g., `task/TLAB-2023` → `TLAB-2023`)
- **Fetches Jira data** via Atlassian CLI (acli)
- **Analyzes git history** - commits, changed files, impacted areas
- **Auto-fills PR templates** with intelligent content:
  - Description → Jira ticket description + commit messages
  - Jira Ticket → Actual ticket URL
  - Impacted Areas → Changed directories/files
  - Replaces placeholder URLs (e.g., `JIRA-0000`)
- **PR title format**: `[JIRA-XXX] - Task Title`
- Supports draft PRs and dry-run preview

## Prerequisites

```bash
brew install gh jq
brew install atlassian-labs/tap/acli
```

## Setup

### 1. Authenticate GitHub CLI
```bash
gh auth login
```

### 2. Authenticate Atlassian CLI
```bash
acli auth login
```
This opens a browser for OAuth authentication.

### 3. Add to PATH
Add to `~/.zshrc`:
```bash
export PATH="$PATH:/path/to/automate-pr"
```

### 4. Verify
```bash
acli auth status
gh auth status
```

## Usage

```bash
cd /path/to/your/repo
git checkout task/TLAB-2023

# Preview the PR
auto-pr --dry-run

# Create PR
auto-pr

# Create as draft
auto-pr --draft

# Target different base branch
auto-pr --base develop
```

## How It Works

### 1. Extracts Jira Ticket
From branch names like:
- `task/TLAB-2023`
- `feature/PROJ-123-add-login`
- `bugfix/ABC-456`

### 2. Fetches Jira Data
Using `acli jira workitem view`:
- Title (used in PR title)
- Description (added to PR body)
- Type (Task, Bug, Story, etc.)
- Status

### 3. Analyzes Git Changes
- Commit messages since base branch
- Changed files
- Impacted directories

### 4. Fills PR Template
Detects and fills common sections:

| Section | Content |
|---------|---------|
| `## Description` / `## Added in this PR` | Jira description + commits |
| `## JIRA Ticket` / `## Jira Ticket` | Ticket URL |
| `## Impacted Areas` | Changed directories |
| `## Type of Change` | Jira issue type |

Also replaces placeholder URLs like `https://company.atlassian.net/browse/JIRA-0000`.

## Example Output

```
PR Title: [TLAB-2023] - [AN] - [SPIKE] - Draft Epic for Live chat integration

PR Body:
## Description
**Jira Description:** Review the attached documentation from Telus Chat SDK...

**Commits:**
- feat: add chat SDK integration
- fix: handle connection errors

## Jira Ticket
https://everlong.atlassian.net/browse/TLAB-2023

## Impacted Areas
- `src/chat`
- `tests/chat`

## Checklist
- [ ] Self-review completed
- [ ] Tests added/updated
```

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview PR without creating |
| `--draft`, `-d` | Create as draft PR |
| `--base`, `-b` | Base branch (default: main) |
| `--setup-help` | Show setup instructions |
| `--help`, `-h` | Show help |

## Supported PR Template Locations

1. `.github/PULL_REQUEST_TEMPLATE.md`
2. `.github/pull_request_template.md`
3. `.github/PULL_REQUEST_TEMPLATE/pull_request_template.md`
4. `docs/PULL_REQUEST_TEMPLATE.md`
5. `PULL_REQUEST_TEMPLATE.md`

## Troubleshooting

### "Atlassian CLI is not authenticated"
```bash
acli auth login
```

### "Could not extract Jira ticket from branch"
Ensure branch name contains ticket ID: `task/PROJ-123`

### "Failed to fetch Jira ticket"
```bash
acli jira workitem view PROJ-123  # Test manually
```

## License

MIT
