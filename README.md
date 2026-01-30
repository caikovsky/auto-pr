# Auto-PR: Automated Pull Request Creator

A CLI tool that automatically creates GitHub Pull Requests using **Atlassian CLI (acli)**. It extracts the Jira ticket from your branch name, fetches ticket details, and creates a PR with the proper format.

## Features

- Extracts Jira ticket ID from branch name (e.g., `task/TLAB-2023` → `TLAB-2023`)
- Fetches ticket title and description using **acli**
- Automatically finds and fills PR templates
- Creates PRs with title format: `[JIRA-XXX] - Task Title`
- Inserts Jira ticket link into PR description
- Supports draft PRs
- Dry-run mode for preview

## Prerequisites

### 1. Install Required Tools

```bash
brew install gh jq
brew install atlassian-labs/tap/acli
```

### 2. Configure GitHub CLI

```bash
gh auth login
```

Follow the prompts to authenticate.

### 3. Configure Atlassian CLI

```bash
acli auth login
```

This opens a browser for OAuth authentication. Log in with your Atlassian account and authorize the CLI.

### 4. Verify Setup

```bash
# Test Atlassian CLI
acli auth status                    # Shows authenticated accounts
acli jira workitem view PROJ-123    # View a ticket

# Test GitHub CLI
gh auth status                      # Shows authentication status
```

## Installation

```bash
# Make executable (already done)
chmod +x /Users/caique-maurano/Script/automate-pr/auto-pr

# Add to PATH (add this line to ~/.zshrc)
export PATH="$PATH:/Users/caique-maurano/Script/automate-pr"

# Reload shell
source ~/.zshrc
```

## Usage

### Basic Usage

```bash
cd /path/to/your/repo
git checkout task/TLAB-2023
git push -u origin HEAD
auto-pr
```

### Options

```bash
auto-pr --help           # Show help
auto-pr --setup-help     # Show setup instructions
auto-pr --draft          # Create as draft PR
auto-pr --base develop   # Use 'develop' as base branch
auto-pr --dry-run        # Preview without creating
```

### Examples

```bash
# Create a draft PR targeting 'develop' branch
auto-pr --draft --base develop

# Preview what the PR will look like
auto-pr --dry-run
```

## Branch Naming Convention

| Branch Name | Extracted Ticket |
|-------------|------------------|
| `task/TLAB-2023` | `TLAB-2023` |
| `feature/PROJ-123-add-login` | `PROJ-123` |
| `bugfix/ABC-456` | `ABC-456` |

## PR Template Support

The script finds PR templates in these locations:

1. `.github/PULL_REQUEST_TEMPLATE.md`
2. `.github/pull_request_template.md`
3. `.github/PULL_REQUEST_TEMPLATE/pull_request_template.md`
4. `docs/PULL_REQUEST_TEMPLATE.md`
5. `PULL_REQUEST_TEMPLATE.md`

### Template Placeholders

| Placeholder | Replaced With |
|-------------|---------------|
| `<!-- Link to Jira ticket -->` | Jira ticket URL |
| `[JIRA_LINK]` | Jira ticket URL |
| `{JIRA_LINK}` | Jira ticket URL |
| `<!-- Describe your changes -->` | Jira ticket description |
| `<!-- What type of change is this? -->` | Jira issue type |

## ACLI Quick Reference

```bash
acli auth login                         # Authenticate via OAuth
acli auth status                        # Check auth status
acli auth logout                        # Logout
acli jira workitem view KEY-123         # View ticket
acli jira workitem view KEY-123 --json  # View ticket as JSON
```

## Troubleshooting

### "Atlassian CLI is not authenticated"
```bash
acli auth login
```

### "GitHub CLI is not authenticated"
```bash
gh auth login
```

### "Could not extract Jira ticket from branch name"
Ensure your branch contains a ticket ID like `PROJ-123`.

## License

MIT
