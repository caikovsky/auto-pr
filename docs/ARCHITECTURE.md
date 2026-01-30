# Architecture Guidelines

> **Principle**: CLEAN Architecture - dependencies point inward, domain has no external dependencies.

---

## Layer Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        CLI Layer                            │
│                  (Typer, user interaction)                  │
├─────────────────────────────────────────────────────────────┤
│                    Application Layer                        │
│              (Use cases, orchestration)                     │
├─────────────────────────────────────────────────────────────┤
│                   Infrastructure Layer                      │
│        (AI providers, Git, Jira, GitHub clients)           │
├─────────────────────────────────────────────────────────────┤
│                      Domain Layer                           │
│          (Entities, interfaces - NO dependencies)           │
└─────────────────────────────────────────────────────────────┘
```

**Dependency Rule**: Outer layers depend on inner layers. Never the reverse.

---

## Layer Responsibilities

### 1. Domain Layer (`auto_pr/domain/`)

The core of the application. **Zero external dependencies**.

**Contains:**
- **Entities**: Immutable data structures (Pydantic frozen models)
- **Interfaces**: Abstract base classes defining contracts

**Rules:**
- ✗ NO imports from other layers
- ✗ NO external libraries (except Pydantic for entities)
- ✗ NO I/O operations
- ✓ Pure Python + type hints
- ✓ Business logic validation

```python
# ✓ GOOD - Domain entity
from pydantic import BaseModel, ConfigDict

class JiraTicket(BaseModel):
    model_config = ConfigDict(frozen=True)
    key: str
    title: str

# ✗ BAD - Domain importing infrastructure
from auto_pr.infrastructure.jira import fetch_ticket  # NEVER DO THIS
```

### 2. Infrastructure Layer (`auto_pr/infrastructure/`)

Implements interfaces defined in Domain. Handles external systems.

**Contains:**
- AI provider implementations (Gemini, Copilot, Agent)
- Jira client (via acli)
- Git client (via git CLI)
- GitHub client (via gh CLI)

**Rules:**
- ✓ Implements domain interfaces
- ✓ Can import from domain
- ✗ Cannot import from application or CLI
- ✓ Handles external I/O, subprocess calls
- ✓ Converts external data to domain entities

```python
# ✓ GOOD - Infrastructure implementing domain interface
from auto_pr.domain.interfaces import AIProvider
from auto_pr.domain.entities import PRDescription

class GeminiProvider(AIProvider):
    def generate(self, prompt: str) -> PRDescription:
        result = subprocess.run(["gemini", "-o", "text"], ...)
        return PRDescription(content=result.stdout)
```

### 3. Application Layer (`auto_pr/application/`)

Orchestrates use cases. Coordinates domain and infrastructure.

**Contains:**
- Use cases (one class per user action)
- Services (shared logic like prompt building)

**Rules:**
- ✓ Imports from domain (entities, interfaces)
- ✓ Receives infrastructure via dependency injection
- ✗ Does NOT instantiate infrastructure directly
- ✓ Contains application-specific business logic
- ✓ Coordinates multiple operations

```python
# ✓ GOOD - Use case with injected dependencies
from auto_pr.domain.interfaces import AIProvider, JiraClient, GitClient

class GeneratePRDescription:
    def __init__(
        self,
        ai_provider: AIProvider,      # Injected, not created
        jira_client: JiraClient,
        git_client: GitClient,
    ):
        self._ai = ai_provider
        self._jira = jira_client
        self._git = git_client
    
    def execute(self, branch: str) -> PRDescription:
        ticket = self._jira.fetch(branch)
        context = self._git.get_context()
        prompt = self._build_prompt(ticket, context)
        return self._ai.generate(prompt)
```

### 4. CLI Layer (`auto_pr/cli/`)

User interface. Handles input/output, wires dependencies.

**Contains:**
- Typer app and commands
- Output formatting (colors, progress)
- Dependency wiring (composition root)

**Rules:**
- ✓ Only layer that creates concrete implementations
- ✓ Passes dependencies to application layer
- ✓ Handles user input/output
- ✓ Catches and displays errors

```python
# ✓ GOOD - CLI wiring dependencies
from auto_pr.infrastructure.ai import GeminiProvider
from auto_pr.application.use_cases import GeneratePRDescription

@app.command()
def main(gemini: bool = False):
    # Composition root - wire dependencies here
    ai_provider = GeminiProvider() if gemini else auto_detect()
    jira_client = AcliJiraClient()
    git_client = GitClientImpl()
    
    use_case = GeneratePRDescription(ai_provider, jira_client, git_client)
    result = use_case.execute(branch)
    
    console.print(result)
```

---

## Directory Structure

```
auto_pr/
├── __init__.py
├── __main__.py                 # Entry: python -m auto_pr
│
├── domain/                     # Layer 1: Core (no deps)
│   ├── __init__.py
│   ├── entities/
│   │   ├── __init__.py
│   │   ├── jira_ticket.py
│   │   ├── git_context.py
│   │   ├── pr_description.py
│   │   └── ai_result.py
│   └── interfaces/
│       ├── __init__.py
│       ├── ai_provider.py
│       ├── jira_client.py
│       ├── git_client.py
│       └── pr_client.py
│
├── infrastructure/             # Layer 2: External systems
│   ├── __init__.py
│   ├── ai/
│   │   ├── __init__.py
│   │   ├── gemini.py
│   │   ├── copilot.py
│   │   └── agent.py
│   ├── jira/
│   │   ├── __init__.py
│   │   └── acli_client.py
│   ├── git/
│   │   ├── __init__.py
│   │   └── client.py
│   └── github/
│       ├── __init__.py
│       └── gh_client.py
│
├── application/                # Layer 3: Use cases
│   ├── __init__.py
│   ├── use_cases/
│   │   ├── __init__.py
│   │   ├── generate_pr.py
│   │   ├── compare_ai.py
│   │   └── create_pr.py
│   └── services/
│       ├── __init__.py
│       ├── prompt_builder.py
│       └── ai_detector.py
│
├── cli/                        # Layer 4: User interface
│   ├── __init__.py
│   ├── app.py
│   ├── commands/
│   │   ├── __init__.py
│   │   └── main.py
│   └── output/
│       ├── __init__.py
│       └── console.py
│
└── config/                     # Configuration
    ├── __init__.py
    └── settings.py
```

---

## Dependency Injection

We use **manual wiring** (no DI framework) for simplicity.

### Composition Root

All dependencies are wired in the CLI layer:

```python
# auto_pr/cli/app.py

def create_use_case(ai_choice: str | None) -> GeneratePRDescription:
    """Composition root - wire all dependencies."""
    
    # Infrastructure
    ai_provider = _get_ai_provider(ai_choice)
    jira_client = AcliJiraClient()
    git_client = GitClientImpl()
    
    # Application
    return GeneratePRDescription(
        ai_provider=ai_provider,
        jira_client=jira_client,
        git_client=git_client,
    )
```

### Why Manual Wiring?

- Simple to understand
- No magic or hidden behavior
- Easy to trace dependencies
- Sufficient for a CLI tool of this size

---

## Data Flow

```
User Input (CLI)
      │
      ▼
┌─────────────────┐
│   CLI Layer     │ ──► Parse args, wire deps
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Application    │ ──► Orchestrate use case
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌───────┐ ┌───────┐
│ Jira  │ │  Git  │ ──► Fetch data (Infrastructure)
└───┬───┘ └───┬───┘
    │         │
    ▼         ▼
┌─────────────────┐
│ Domain Entities │ ──► JiraTicket, GitContext (frozen)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  AI Provider    │ ──► Generate description (Infrastructure)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PRDescription   │ ──► Domain entity (frozen)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   CLI Output    │ ──► Display to user
└─────────────────┘
```

---

## Configuration Principles

### Single Source of Truth

All configuration defaults live in **one place**: `DEFAULT_CONFIG` in `config/settings.py`.

```python
# ✓ GOOD - One source
DEFAULT_CONFIG = '''
ai_provider = "auto"
prompt_instructions = "..."
'''

# Config file auto-created from DEFAULT_CONFIG if missing
def load_settings() -> Settings:
    config_path = _ensure_config_exists()  # Creates from DEFAULT_CONFIG
    return Settings(**tomllib.load(config_path))
```

```python
# ✗ BAD - Multiple sources (hardcoded fallbacks)
class Settings:
    prompt_instructions: str = "default here"  # NO! Duplicates DEFAULT_CONFIG
```

### User Choice

Always prompt before ambiguous or potentially destructive actions:

```python
# ✓ GOOD - Ask user
if existing_pr and not force_update:
    choice = typer.prompt("[U]pdate or [N]ew?", default="U")

# ✗ BAD - Assume behavior
if existing_pr:
    update_pr(existing_pr)  # User didn't consent!
```

---

## Rules Summary

| Rule | Description |
|------|-------------|
| **Dependency Direction** | Always inward (CLI → App → Infra → Domain) |
| **Domain Purity** | No external imports in domain |
| **Interface Segregation** | Small, focused interfaces |
| **Dependency Inversion** | Depend on interfaces, not implementations |
| **Single Responsibility** | One reason to change per class |
| **Composition Root** | Wire dependencies in CLI only |
| **Single Source of Truth** | Config file for defaults, no hardcoded fallbacks |
| **User Choice** | Prompt before ambiguous/destructive actions |
