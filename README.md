# autopr

AI-powered Pull Request creation tool. Automatically generates PR descriptions using AI based on your Jira ticket and git changes.

## Quick Start

```bash
# Install globally (one-time setup)
pipx install git+https://github.com/caikovsky/auto-pr.git

# Navigate to any git repository
cd your-project

# Create a PR with AI-generated description
autopr

# Or preview first
autopr --dry-run
```

## Features

- **AI-Powered Descriptions**: Uses Gemini, GitHub Copilot, or Cursor Agent to generate insightful PR descriptions
- **Jira Integration**: Automatically fetches ticket details from Jira via Atlassian CLI
- **Git Context**: Analyzes commits, changed files, and diffs to provide technical context
- **PR Template Support**: Fills your repository's PR template automatically
- **Multiple AI Providers**: Choose between Gemini, Copilot, or Agent (or let it auto-detect)
- **Comparison Mode**: Compare outputs from all AI providers side-by-side

## Installation

### Prerequisites

- Python 3.12+
- [Atlassian CLI (acli)](https://www.atlassian.com/software/cli) - for Jira integration
- [GitHub CLI (gh)](https://cli.github.com/) - for PR creation
- At least one AI CLI: `gemini`, `copilot`, or `agent`

### Install Globally (Recommended)

#### Option 1: Using pipx (Recommended)

```bash
# Install pipx if you don't have it
brew install pipx
pipx ensurepath

# Install autopr
pipx install git+https://github.com/caikovsky/auto-pr.git

# Verify
autopr --help
```

#### Option 2: Using uv tool

```bash
uv tool install git+https://github.com/caikovsky/auto-pr.git
autopr --help
```

#### Option 3: Clone and Install

```bash
git clone https://github.com/caikovsky/auto-pr.git
cd auto-pr
pipx install .
```

### Install for Development

```bash
git clone https://github.com/caikovsky/auto-pr.git
cd auto-pr
uv sync
uv run autopr --help
```

## Usage

### Basic Usage

```bash
# Generate and create a PR (auto-detects AI provider)
autopr

# Preview without creating PR
autopr --dry-run

# Create as draft PR
autopr --draft
```

### AI Provider Selection

```bash
# Use specific AI provider
autopr --gemini
autopr --copilot
autopr --agent

# Auto-detect (default): tries gemini -> copilot -> agent
autopr
```

### Other Options

```bash
# Specify base branch
autopr --base develop

# Verbose output (show full PR description)
autopr --verbose

# Compare all AI providers
autopr --test
autopr --test --test-dir ./results
```

### All Options

```
Usage: autopr [OPTIONS]

Options:
  -n, --dry-run        Preview without creating PR
  -d, --draft          Create as draft PR
  -b, --base TEXT      Base branch for PR [default: main]
  --gemini             Use Gemini AI
  --copilot            Use GitHub Copilot
  --agent              Use Cursor Agent
  --test               Compare all AI providers
  --test-dir PATH      Output directory for --test
  -v, --verbose        Verbose output
  --help               Show this message and exit.
```

## Configuration

Config file: `~/.config/autopr/config.toml`

```toml
# AI provider: auto, gemini, copilot, or agent
ai_provider = "auto"

# Default base branch for PRs
base_branch = "main"

# Jira instance URL
jira_base_url = "https://your-company.atlassian.net"
```

## Branch Naming Convention

The tool extracts Jira ticket keys from branch names:

- `task/PROJ-123`
- `feature/PROJ-123-description`
- `fix/PROJ-123-bug-fix`
- `PROJ-123-any-description`

The pattern `[A-Z]+-[0-9]+` is matched anywhere in the branch name.

## Updating

```bash
pipx upgrade autopr

# Or reinstall from latest
pipx install --force git+https://github.com/caikovsky/auto-pr.git
```

## Uninstall

```bash
pipx uninstall autopr
```

## Architecture

This tool follows CLEAN architecture principles:

```
auto_pr/
├── domain/          # Entities, interfaces, exceptions (no dependencies)
├── infrastructure/  # External tool implementations (git, jira, ai, github)
├── application/     # Use cases and services
├── cli/             # Typer CLI application
└── config/          # Settings management
```

See `docs/` for detailed architecture and style guidelines.

## Development

```bash
uv sync --all-extras
uv run pytest
uv run mypy auto_pr
uv run ruff check auto_pr
```

## License

MIT
