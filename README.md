# Auto-PR: AI-Powered Pull Request Generator

A CLI tool that uses **AI** to automatically create intelligent GitHub Pull Requests. It analyzes your code changes, compares them to Jira ticket requirements, and generates comprehensive PR descriptions.

## Supported AI CLIs

| CLI | Command | Description |
|-----|---------|-------------|
| **Gemini** | `gemini` | Google Gemini CLI |
| **Copilot** | `copilot` | GitHub Copilot CLI |
| **Agent** | `agent` | Cursor Agent CLI |

## Prerequisites

```bash
# Core tools
brew install gh jq
brew install atlassian-labs/tap/acli

# AI CLI (at least one)
brew install gemini-cli    # Google Gemini
```

## Setup

```bash
# Authenticate
gh auth login
acli auth login

# Add to PATH (in ~/.zshrc)
export PATH="$PATH:/path/to/automate-pr"
source ~/.zshrc
```

## Usage

```bash
cd /path/to/your/repo
git checkout task/TLAB-2023

auto-pr --dry-run    # Preview AI-generated PR
auto-pr              # Create PR
auto-pr --draft      # Create as draft
```

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview PR without creating |
| `--draft`, `-d` | Create as draft PR |
| `--base`, `-b` | Base branch (default: main) |
| `--test [dir]` | Compare outputs from gemini, copilot, agent |
| `--setup` | Configure AI CLI tool |
| `--help`, `-h` | Show help |

## AI Comparison Testing

Compare results from different AI CLIs to find the best one:

```bash
auto-pr --test                    # Saves to ./auto-pr-test-TIMESTAMP/
auto-pr --test ./my-test-results  # Custom directory
```

Creates:
- `prompt.txt` - The prompt sent to all AIs
- `gemini_output.txt` - Output from Gemini
- `copilot_output.txt` - Output from Copilot
- `agent_output.txt` - Output from Cursor Agent
- `summary.md` - Comparison with timing and word counts

Compare outputs:
```bash
diff -y ./results/gemini_output.txt ./results/copilot_output.txt
cursor --diff ./results/gemini_output.txt ./results/agent_output.txt
```

## Example Output

```markdown
## Summary
This PR transforms the auto-pr tool into an AI-powered PR generator
that analyzes code changes and Jira tickets automatically.

## What Changed
- Added AI CLI integration (Gemini, Copilot, Agent)
- Implemented git diff analysis
- Added Jira ticket context extraction

## Technical Approach
The script extracts git diffs and commit messages, combines them
with Jira ticket data, and sends to the AI for analysis...

## Key Files to Review
- `auto-pr` - Main script with AI integration

## Testing Considerations
- Test with different AI CLIs
- Verify PR descriptions match code changes

## Jira Ticket
https://company.atlassian.net/browse/TLAB-2023
```

## Branch Naming

| Branch | Extracted Ticket |
|--------|-----------------|
| `task/TLAB-2023` | TLAB-2023 |
| `feature/PROJ-123-login` | PROJ-123 |
| `bugfix/ABC-456` | ABC-456 |

## License

MIT
