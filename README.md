# Auto-PR: AI-Powered Pull Request Generator

A CLI tool that uses **AI** to automatically create intelligent GitHub Pull Requests. It analyzes your code changes, compares them to Jira ticket requirements, and generates comprehensive PR descriptions.

## Features

- **AI-Powered Analysis** using Gemini, GitHub Copilot, Claude, or other AI CLIs
- **Jira Integration** via Atlassian CLI (acli)
- **Smart PR Descriptions** that explain what changed and why
- **Multi-AI Testing** to compare outputs from different AI providers
- **Auto-detects** installed AI CLI tools
- PR title format: `[JIRA-XXX] - Task Title`

## Prerequisites

```bash
# Core tools
brew install gh jq
brew install atlassian-labs/tap/acli

# AI CLI (install at least one)
brew install gemini-cli      # Google Gemini (recommended)
# npm install -g copilot     # GitHub Copilot CLI
# brew install llm           # Simon Willison's LLM
# brew install mods          # Charmbracelet Mods
# brew install ollama        # Local models
```

## Setup

```bash
# Authenticate GitHub
gh auth login

# Authenticate Atlassian
acli auth login

# Add to PATH (in ~/.zshrc)
export PATH="$PATH:/path/to/automate-pr"
source ~/.zshrc
```

## Usage

```bash
cd /path/to/your/repo
git checkout task/TLAB-2023

# Preview AI-generated PR
auto-pr --dry-run

# Create PR
auto-pr

# Create as draft
auto-pr --draft
```

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview PR without creating |
| `--draft`, `-d` | Create as draft PR |
| `--base`, `-b` | Base branch (default: main) |
| `--test [dir]` | Compare outputs from multiple AI CLIs |
| `--setup` | Configure AI CLI tool |
| `--help`, `-h` | Show help |

## AI Comparison Testing

Compare results from different AI CLIs:

```bash
# Run comparison test
auto-pr --test

# Or specify output directory
auto-pr --test ./my-test-results
```

Creates:
- `prompt.txt` - The prompt sent to all AIs
- `gemini_output.txt` - Output from Gemini
- `copilot_output.txt` - Output from GitHub Copilot
- `summary.md` - Timing and word counts

Compare:
```bash
diff -y ./my-test-results/gemini_output.txt ./my-test-results/copilot_output.txt
```

## Supported AI CLIs

| CLI | Command | Notes |
|-----|---------|-------|
| Gemini | `gemini` | Google Gemini (recommended) |
| Copilot | `copilot` | GitHub Copilot CLI |
| Claude | `claude` | Anthropic Claude |
| LLM | `llm` | Multi-provider |
| Mods | `mods` | Charmbracelet |
| Ollama | `ollama` | Local models |

## Example Output

```markdown
## Summary
This PR transforms the auto-pr tool into an AI-powered PR generator
that analyzes code changes and Jira tickets to create comprehensive
descriptions automatically.

## What Changed
- Added AI CLI integration (Gemini, Copilot, Claude)
- Implemented git diff analysis
- Added Jira ticket context extraction

## Technical Approach
The script extracts git diffs and commit messages, combines them
with Jira ticket data, and sends to the AI for analysis...

## Key Files to Review
- `auto-pr` - Main script with AI integration
- `README.md` - Updated documentation

## Testing Considerations
- Test with different AI CLIs
- Verify PR descriptions match code changes
```

## Branch Naming

| Branch | Extracted Ticket |
|--------|-----------------|
| `task/TLAB-2023` | TLAB-2023 |
| `feature/PROJ-123-login` | PROJ-123 |
| `bugfix/ABC-456` | ABC-456 |

## Troubleshooting

### "No AI CLI tool found"
```bash
brew install gemini-cli
```

### "Atlassian CLI is not authenticated"
```bash
acli auth login
```

### "GitHub CLI is not authenticated"
```bash
gh auth login
```

## License

MIT
