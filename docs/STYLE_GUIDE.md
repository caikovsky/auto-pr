# Code Style Guide

> **Principle**: Explicit is better than implicit. Type everything.

---

## Tools

| Tool | Purpose | Config |
|------|---------|--------|
| ruff | Linting + formatting | `pyproject.toml` |
| mypy | Type checking (strict) | `pyproject.toml` |

---

## Type Hints

### Rule: Type Everything

```python
# ✓ GOOD - Fully typed
def fetch_ticket(ticket_key: str) -> JiraTicket:
    ...

# ✗ BAD - Missing types
def fetch_ticket(ticket_key):
    ...
```

### No `Any` Type

```python
# ✗ BAD - Avoid Any
def process(data: Any) -> Any:
    ...

# ✓ GOOD - Specific types
def process(data: dict[str, str]) -> ProcessedResult:
    ...
```

### Optional and Union

```python
from typing import Optional

# ✓ GOOD - Use | for unions (Python 3.10+)
def find_ticket(key: str) -> JiraTicket | None:
    ...

# Also acceptable
def find_ticket(key: str) -> Optional[JiraTicket]:
    ...
```

### Collections

```python
# ✓ GOOD - Generic collections (Python 3.9+)
def get_files() -> list[str]:
    ...

def get_config() -> dict[str, str]:
    ...

# For complex types, use type aliases
CommitList = list[str]
FileChanges = dict[str, list[str]]
```

---

## Pydantic Models

### Frozen Models (Entities)

```python
from pydantic import BaseModel, ConfigDict, Field


class JiraTicket(BaseModel):
    """Jira ticket entity (immutable)."""
    
    model_config = ConfigDict(frozen=True)
    
    key: str = Field(pattern=r'^[A-Z]+-\d+$')
    title: str
    description: str = ""
    ticket_type: str
    url: str
```

### Validation

```python
from pydantic import BaseModel, Field, field_validator


class GitContext(BaseModel):
    model_config = ConfigDict(frozen=True)
    
    branch: str
    commits: list[str] = Field(default_factory=list)
    changed_files: list[str] = Field(default_factory=list)
    diff: str = ""
    
    @field_validator("branch")
    @classmethod
    def branch_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Branch cannot be empty")
        return v
```

---

## Classes

### Interfaces (Abstract Base Classes)

```python
from abc import ABC, abstractmethod


class AIProvider(ABC):
    """Interface for AI providers."""
    
    @property
    @abstractmethod
    def name(self) -> str:
        """Provider name for display."""
        ...
    
    @abstractmethod
    def generate(self, prompt: str) -> PRDescription:
        """Generate PR description from prompt."""
        ...
```

### Implementations

```python
class GeminiProvider(AIProvider):
    """Google Gemini AI provider."""
    
    @property
    def name(self) -> str:
        return "gemini"
    
    def generate(self, prompt: str) -> PRDescription:
        result = self._execute_cli(prompt)
        return PRDescription(content=result)
    
    def _execute_cli(self, prompt: str) -> str:
        """Execute gemini CLI. Private method."""
        ...
```

### Naming

| Type | Convention | Example |
|------|------------|---------|
| Class | PascalCase | `JiraTicket` |
| Interface | PascalCase | `AIProvider` |
| Implementation | PascalCase + Suffix | `GeminiProvider` |
| Method | snake_case | `fetch_ticket` |
| Private method | _snake_case | `_parse_response` |
| Constant | UPPER_SNAKE | `DEFAULT_TIMEOUT` |

---

## Functions

### Docstrings

```python
def fetch_ticket(ticket_key: str) -> JiraTicket:
    """Fetch Jira ticket by key.
    
    Args:
        ticket_key: The Jira ticket key (e.g., "TLAB-123").
    
    Returns:
        The fetched JiraTicket entity.
    
    Raises:
        JiraTicketNotFoundError: If ticket doesn't exist.
        JiraAuthenticationError: If not authenticated.
    """
    ...
```

### Keep Functions Small

```python
# ✗ BAD - Function doing too much
def process_and_create_pr(branch: str) -> str:
    ticket = fetch_ticket(...)
    context = get_git_context(...)
    prompt = build_prompt(...)
    description = generate_description(...)
    pr_url = create_pr(...)
    send_notification(...)
    return pr_url

# ✓ GOOD - Single responsibility
def generate_pr_description(ticket: JiraTicket, context: GitContext) -> PRDescription:
    prompt = build_prompt(ticket, context)
    return ai_provider.generate(prompt)
```

---

## Imports

### Order

```python
# 1. Standard library
import json
import subprocess
from pathlib import Path

# 2. Third-party
from pydantic import BaseModel
from typer import Typer

# 3. Local (absolute imports)
from auto_pr.domain.entities import JiraTicket
from auto_pr.domain.exceptions import JiraError
```

### No Relative Imports

```python
# ✗ BAD - Relative imports
from ..entities import JiraTicket
from .base import BaseProvider

# ✓ GOOD - Absolute imports
from auto_pr.domain.entities import JiraTicket
from auto_pr.infrastructure.ai.base import BaseProvider
```

---

## Error Messages

### User-Facing Errors

```python
# ✓ GOOD - Clear, actionable
raise JiraTicketNotFoundError(
    f"Jira ticket not found: {ticket_key}",
    hint="Check the ticket key and your Jira permissions",
)

# ✗ BAD - Technical jargon
raise Exception(f"404 from JIRA API for key={ticket_key}")
```

---

## Constants

### Module-Level Constants

```python
# auto_pr/config/constants.py

DEFAULT_BASE_BRANCH = "main"
JIRA_TICKET_PATTERN = r'^[A-Z]+-\d+$'
MAX_DIFF_LINES = 800
SUPPORTED_AI_PROVIDERS = ("gemini", "copilot", "agent")
```

---

## File Organization

### One Class Per File (Usually)

```
entities/
├── jira_ticket.py      # JiraTicket class
├── git_context.py      # GitContext class
└── pr_description.py   # PRDescription class
```

### Exceptions: Related Small Classes

```python
# auto_pr/domain/exceptions.py
# OK to have multiple related exceptions in one file

class JiraError(AutoPRError): ...
class JiraTicketNotFoundError(JiraError): ...
class JiraAuthenticationError(JiraError): ...
```

---

## Configuration

### pyproject.toml

```toml
[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = [
    "E",      # pycodestyle errors
    "W",      # pycodestyle warnings
    "F",      # Pyflakes
    "I",      # isort
    "B",      # flake8-bugbear
    "C4",     # flake8-comprehensions
    "UP",     # pyupgrade
]

[tool.mypy]
python_version = "3.12"
strict = true
warn_return_any = true
warn_unused_ignores = true
disallow_untyped_defs = true
disallow_any_generics = true
```

---

## Rules Summary

| Rule | Description |
|------|-------------|
| **Type Everything** | No untyped functions or variables |
| **No Any** | Use specific types always |
| **Frozen Entities** | All domain models are immutable |
| **Absolute Imports** | No relative imports |
| **Docstrings** | All public functions documented |
| **Small Functions** | Single responsibility |
| **Clear Errors** | User-friendly messages with hints |
