# auto-pr

AI-powered Pull Request creation tool. Automatically generates PR descriptions using AI based on your Jira ticket and git changes.

## Quick Start

```bash
# Install globally (one-time setup)
pipx install git+https://github.com/caikovsky/auto-pr.git

# Navigate to any git repository
cd your-project

# Create a PR with AI-generated description
auto-pr

# Or preview first
auto-pr --dry-run
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
- [uv](https://github.com/astral-sh/uv) package manager
- [Atlassian CLI (acli)](https://www.atlassian.com/software/cli) - for Jira integration
- [GitHub CLI (gh)](https://cli.github.com/) - for PR creation
- At least one AI CLI: `gemini`, `copilot`, or `agent`

### Install Globally (Recommended)

This makes `auto-pr` available from anywhere in your terminal.

#### Option 1: Using pipx (Recommended)

```bash
# Install pipx if you don't have it
brew install pipx
pipx ensurepath

# Install auto-pr globally
pipx install git+https://github.com/caikovsky/auto-pr.git

# Verify it works
auto-pr --help
```

#### Option 2: Using uv tool

```bash
# Install globally with uv
uv tool install git+https://github.com/caikovsky/auto-pr.git

# Verify it works
auto-pr --help
```

#### Option 3: Clone and Install

```bash
# Clone the repository
git clone https://github.com/caikovsky/auto-pr.git
cd auto-pr

# Install globally with pipx
pipx install .

# Or with uv
uv tool install .
```

### Install for Development

If you want to modify the tool:

```bash
git clone https://github.com/caikovsky/auto-pr.git
cd auto-pr

# Install in development mode
uv sync

# Run from the project directory
uv run auto-pr --help
```

## Usage

### Basic Usage

```bash
# Generate and create a PR (auto-detects AI provider)
auto-pr

# Preview without creating PR
auto-pr --dry-run

# Create as draft PR
auto-pr --draft
```

### AI Provider Selection

```bash
# Use specific AI provider
auto-pr --gemini
auto-pr --copilot
auto-pr --agent

# Auto-detect (default): tries gemini -> copilot -> agent
auto-pr
```

### Other Options

```bash
# Specify base branch
auto-pr --base develop

# Verbose output (show full PR description)
auto-pr --verbose

# Compare all AI providers
auto-pr --test
auto-pr --test --test-dir ./results
```

### All Options

```
Usage: auto-pr [OPTIONS]

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

The tool extracts Jira ticket keys from branch names. Use formats like:

- `task/PROJ-123`
- `feature/PROJ-123-description`
- `fix/PROJ-123-bug-fix`
- `PROJ-123-any-description`

The pattern `[A-Z]+-[0-9]+` is matched anywhere in the branch name.

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

## Updating

```bash
# If installed with pipx
pipx upgrade auto-pr

# Or reinstall
pipx install --force git+https://github.com/caikovsky/auto-pr.git

# If installed with uv tool
uv tool upgrade auto-pr
```

## Uninstall

```bash
# If installed with pipx
pipx uninstall auto-pr

# If installed with uv tool
uv tool uninstall auto-pr
```

## Development

```bash
# Install with dev dependencies
uv sync --all-extras

# Run tests
uv run pytest

# Type checking
uv run mypy auto_pr

# Linting
uv run ruff check auto_pr
```

## License

MIT
