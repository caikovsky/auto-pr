# Contributing to autopr

Thank you for your interest in contributing to `autopr`! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) - Fast Python package manager
- [GitHub CLI (gh)](https://cli.github.com/) - For testing PR creation
- Git

### Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/caikovsky/auto-pr.git
cd auto-pr

# Install dependencies
uv sync --all-extras

# Verify setup
uv run autopr --help
uv run pytest
```

## Development Workflow

### 1. Create a Branch

Always work on a feature branch, never directly on `main`:

```bash
git checkout main
git pull origin main
git checkout -b feature/your-feature-name
```

Branch naming conventions:
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation changes
- `refactor/description` - Code refactoring

### 2. Make Your Changes

Follow the project's architecture and style guidelines:

- **Architecture**: See `docs/ARCHITECTURE.md`
- **Style Guide**: See `docs/STYLE_GUIDE.md`
- **Error Handling**: See `docs/ERROR_HANDLING.md`
- **Testing**: See `docs/TESTING.md`

### 3. Run Quality Checks

Before committing, ensure all checks pass:

```bash
# Run tests
uv run pytest

# Type checking
uv run mypy auto_pr

# Linting
uv run ruff check auto_pr

# Format code
uv run ruff format auto_pr
```

### 4. Commit Your Changes

Write clear, descriptive commit messages:

```bash
git add .
git commit -m "feat: add support for GitLab"
```

Commit message format:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation only
- `refactor:` - Code change that neither fixes a bug nor adds a feature
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

### 5. Create a Pull Request

```bash
# Push your branch
git push -u origin feature/your-feature-name

# Create PR via GitHub CLI
gh pr create --title "feat: your feature" --body "Description of changes"
```

Or create via GitHub UI at https://github.com/caikovsky/auto-pr/pulls

## Pull Request Guidelines

### PR Title

Use the same format as commit messages:
- `feat: add support for GitLab`
- `fix: handle empty diff gracefully`
- `docs: update installation instructions`

### PR Description

Include:
- **What**: Brief description of the change
- **Why**: Motivation or issue being solved
- **How**: Technical approach (for complex changes)
- **Testing**: How you tested the changes

### Review Process

1. All PRs require review before merging
2. Address review feedback promptly
3. Keep PRs focused and reasonably sized
4. Ensure CI checks pass

## What to Contribute

### Good First Contributions

- Documentation improvements
- Bug fixes with clear reproduction steps
- Test coverage improvements
- Typo fixes

### Feature Ideas

Before starting a large feature:
1. Open an issue to discuss the idea
2. Get feedback on the approach
3. Then implement

Current areas open for contribution:
- Additional AI provider integrations
- Support for other issue trackers (Linear, Asana)
- Support for other Git platforms (GitLab, Bitbucket)
- Improved error messages and hints
- Test coverage expansion

## Code Guidelines

### Architecture Rules

This project follows CLEAN architecture:

```
auto_pr/
├── domain/          # Entities, interfaces (NO external dependencies)
├── infrastructure/  # External integrations (git, jira, ai, github)
├── application/     # Use cases and services
├── cli/             # User interface (Typer)
└── config/          # Settings management
```

**Key principles:**
- Dependencies point inward (CLI → Application → Infrastructure → Domain)
- Domain layer has zero external dependencies
- Depend on interfaces, not implementations

### Style Rules

- Type hints on all functions
- Docstrings on public functions and classes
- Immutable entities (Pydantic `frozen=True`)
- No hardcoded defaults in code (use config file)

### Testing Rules

- Unit tests for domain and application layers
- Integration tests for infrastructure
- Use fixtures from `tests/conftest.py`
- Aim for meaningful tests, not just coverage

## Reporting Issues

### Bug Reports

Include:
- Python version (`python --version`)
- OS and version
- Steps to reproduce
- Expected vs actual behavior
- Error messages (full traceback)

### Feature Requests

Include:
- Use case description
- Proposed solution (if any)
- Alternatives considered

## Questions?

- Open an issue for questions about contributing
- Check existing issues and PRs for context

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
