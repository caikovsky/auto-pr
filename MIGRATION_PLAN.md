# Auto-PR v2: Python Migration Plan

> **Status**: Planning  
> **Created**: 2026-01-30  
> **Branch**: `feature/python-migration`  
> **Bash preserved in**: `bash-v1` branch

---

## Overview

Migrate `auto-pr` from a bash script to a Python CLI application using CLEAN architecture principles.

### Goals

- [ ] Same CLI interface as bash version
- [ ] CLEAN architecture (maintainable by AI and humans)
- [ ] Type-safe with full mypy coverage
- [ ] Testable with pytest
- [ ] Installable via pipx
- [ ] Extensible for new AI providers

### Tech Stack

| Component | Choice |
|-----------|--------|
| Python | 3.12+ |
| Package Manager | uv |
| CLI Framework | Typer |
| Testing | pytest |
| Type Checking | mypy |
| Linting | ruff |

---

## Phase 1: Project Setup

### Tasks

- [ ] 1.1 Create Python project structure
- [ ] 1.2 Configure `pyproject.toml` with uv
- [ ] 1.3 Set up development dependencies (pytest, mypy, ruff)
- [ ] 1.4 Create basic CLI entry point
- [ ] 1.5 Verify `pipx install .` works

### Questions to Resolve

1. **Project name**: Keep `auto-pr` or rename to `autopr`? (pip doesn't like hyphens in package names)
2. **Source layout**: `src/auto_pr/` or flat `auto_pr/`?

### Acceptance Criteria

```bash
# Should work after Phase 1
pipx install .
auto-pr --help
auto-pr --version
```

---

## Phase 2: Domain Layer (Core Business Logic)

### Architecture

```
auto_pr/
└── domain/
    ├── __init__.py
    ├── entities/
    │   ├── __init__.py
    │   ├── jira_ticket.py      # JiraTicket dataclass
    │   ├── git_context.py      # GitContext dataclass
    │   ├── pr_description.py   # PRDescription dataclass
    │   └── ai_result.py        # AIResult dataclass
    └── interfaces/
        ├── __init__.py
        ├── ai_provider.py      # Abstract AIProvider
        ├── jira_client.py      # Abstract JiraClient
        ├── git_client.py       # Abstract GitClient
        └── pr_client.py        # Abstract PRClient (GitHub)
```

### Tasks

- [ ] 2.1 Define `JiraTicket` entity
- [ ] 2.2 Define `GitContext` entity (branch, commits, diff, changed files)
- [ ] 2.3 Define `PRDescription` entity
- [ ] 2.4 Define `AIResult` entity (for comparison testing)
- [ ] 2.5 Define `AIProvider` interface (abstract base class)
- [ ] 2.6 Define `JiraClient` interface
- [ ] 2.7 Define `GitClient` interface
- [ ] 2.8 Define `PRClient` interface

### Questions to Resolve

1. Should entities be immutable (`frozen=True` dataclasses)?
2. Use `dataclasses` or `pydantic` for validation?

### Acceptance Criteria

- All entities have type hints
- All interfaces are abstract (ABC)
- No external dependencies in domain layer
- 100% test coverage for entities

---

## Phase 3: Infrastructure Layer (External Integrations)

### Architecture

```
auto_pr/
└── infrastructure/
    ├── __init__.py
    ├── ai/
    │   ├── __init__.py
    │   ├── base.py             # Shared CLI execution logic
    │   ├── gemini_provider.py
    │   ├── copilot_provider.py
    │   └── agent_provider.py
    ├── jira/
    │   ├── __init__.py
    │   └── acli_client.py      # Uses `acli` CLI
    ├── git/
    │   ├── __init__.py
    │   └── git_client.py       # Uses `git` CLI
    └── github/
        ├── __init__.py
        └── gh_client.py        # Uses `gh` CLI
```

### Tasks

- [ ] 3.1 Implement `GitClientImpl` (extract branch, commits, diff)
- [ ] 3.2 Implement `AcliJiraClient` (fetch ticket via acli)
- [ ] 3.3 Implement `GeminiProvider`
- [ ] 3.4 Implement `CopilotProvider`
- [ ] 3.5 Implement `AgentProvider`
- [ ] 3.6 Implement `GhPRClient` (create PR via gh)
- [ ] 3.7 Add subprocess wrapper with error handling

### Questions to Resolve

1. Use `subprocess` directly or a wrapper library?
2. Async or sync execution for CLI calls?
3. How to handle CLI tool not installed errors?

### Acceptance Criteria

- Each provider implements the interface correctly
- Proper error handling for missing CLI tools
- Integration tests with mocked subprocess

---

## Phase 4: Application Layer (Use Cases)

### Architecture

```
auto_pr/
└── application/
    ├── __init__.py
    ├── use_cases/
    │   ├── __init__.py
    │   ├── generate_pr.py          # Main use case
    │   ├── compare_ai_outputs.py   # --test flag
    │   └── create_pull_request.py  # gh pr create
    └── services/
        ├── __init__.py
        ├── prompt_builder.py       # Build AI prompt
        └── ai_selector.py          # Select/detect AI provider
```

### Tasks

- [ ] 4.1 Implement `PromptBuilder` service
- [ ] 4.2 Implement `AISelector` service (auto-detect, explicit selection)
- [ ] 4.3 Implement `GeneratePRDescription` use case
- [ ] 4.4 Implement `CompareAIOutputs` use case
- [ ] 4.5 Implement `CreatePullRequest` use case

### Questions to Resolve

1. Should use cases return `Result[T, Error]` or raise exceptions?
2. How to handle partial failures in comparison mode?

### Acceptance Criteria

- Use cases are testable with mocked dependencies
- No direct infrastructure imports (dependency injection)
- Clear separation between orchestration and business logic

---

## Phase 5: CLI Layer (Presentation)

### Architecture

```
auto_pr/
├── __init__.py
├── __main__.py          # python -m auto_pr
└── cli/
    ├── __init__.py
    ├── app.py           # Typer app definition
    ├── commands/
    │   ├── __init__.py
    │   ├── generate.py  # Main command (default)
    │   └── test.py      # --test comparison
    └── output/
        ├── __init__.py
        ├── console.py   # Rich console output
        └── files.py     # File output for --test
```

### Tasks

- [ ] 5.1 Create Typer app with main command
- [ ] 5.2 Implement `--gemini`, `--copilot`, `--agent` flags
- [ ] 5.3 Implement `--dry-run` flag
- [ ] 5.4 Implement `--draft` flag
- [ ] 5.5 Implement `--base` option
- [ ] 5.6 Implement `--test` command
- [ ] 5.7 Add Rich console output (colors, progress)
- [ ] 5.8 Add shell completion support

### Questions to Resolve

1. Use Rich for output formatting?
2. Add `--verbose` / `--quiet` flags?
3. Add `--version` flag?

### Acceptance Criteria

```bash
# All these should work identically to bash version
auto-pr --help
auto-pr --gemini --dry-run
auto-pr --copilot --draft
auto-pr --agent --base develop
auto-pr --test ./results
```

---

## Phase 6: Configuration & DI

### Architecture

```
auto_pr/
└── config/
    ├── __init__.py
    ├── settings.py      # Pydantic settings
    └── container.py     # Dependency injection
```

### Tasks

- [ ] 6.1 Create settings class (config file path, defaults)
- [ ] 6.2 Implement simple DI container
- [ ] 6.3 Wire up all dependencies

### Questions to Resolve

1. Use a DI library (dependency-injector) or manual wiring?
2. Config file format: TOML, YAML, or just env vars?

---

## Phase 7: Testing

### Structure

```
tests/
├── __init__.py
├── conftest.py              # Shared fixtures
├── unit/
│   ├── domain/
│   │   └── test_entities.py
│   ├── application/
│   │   └── test_use_cases.py
│   └── infrastructure/
│       └── test_providers.py
├── integration/
│   └── test_cli.py
└── fixtures/
    ├── jira_response.json
    └── git_diff.txt
```

### Tasks

- [ ] 7.1 Set up pytest configuration
- [ ] 7.2 Create test fixtures
- [ ] 7.3 Write unit tests for domain entities
- [ ] 7.4 Write unit tests for use cases (mocked deps)
- [ ] 7.5 Write integration tests for CLI
- [ ] 7.6 Achieve >80% coverage

---

## Phase 8: Documentation & Packaging

### Tasks

- [ ] 8.1 Update README.md for Python version
- [ ] 8.2 Add installation instructions (pipx)
- [ ] 8.3 Add CONTRIBUTING.md
- [ ] 8.4 Add CHANGELOG.md
- [ ] 8.5 Configure GitHub Actions for CI
- [ ] 8.6 Publish to PyPI (optional)

---

## Migration Checklist

### Feature Parity with Bash v1

- [ ] Extract Jira ticket from branch name
- [ ] Fetch ticket details via `acli`
- [ ] Get git context (commits, diff, changed files)
- [ ] Build AI prompt
- [ ] Call Gemini CLI
- [ ] Call Copilot CLI
- [ ] Call Agent CLI
- [ ] Auto-detect available AI CLI
- [ ] `--gemini` flag
- [ ] `--copilot` flag
- [ ] `--agent` flag
- [ ] `--dry-run` flag
- [ ] `--draft` flag
- [ ] `--base` option
- [ ] `--test` comparison mode
- [ ] Create PR via `gh`
- [ ] Colored console output
- [ ] Error handling for missing tools

---

## Open Questions

> Add questions here as they come up during implementation

1. 
2. 
3. 

---

## Session Log

> Track progress across sessions here

### Session 1 - 2026-01-30
- Created migration plan
- Set up branch structure (`bash-v1`, `feature/python-migration`)
- Defined tech stack and phases

### Session 2 - TBD
- 

