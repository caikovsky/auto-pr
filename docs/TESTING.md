# Testing Guidelines

> **Principle**: Test behavior, not implementation. Mock at boundaries.

---

## Testing Stack

| Tool | Purpose |
|------|---------|
| pytest | Test framework |
| pytest-cov | Coverage reporting |
| pytest-asyncio | Async test support (if needed) |

---

## Test Structure

```
tests/
├── __init__.py
├── conftest.py                 # Shared fixtures
│
├── unit/                       # Fast, isolated tests
│   ├── __init__.py
│   ├── domain/
│   │   ├── __init__.py
│   │   ├── test_jira_ticket.py
│   │   ├── test_git_context.py
│   │   └── test_pr_description.py
│   ├── application/
│   │   ├── __init__.py
│   │   ├── test_generate_pr.py
│   │   ├── test_compare_ai.py
│   │   └── test_prompt_builder.py
│   └── infrastructure/
│       ├── __init__.py
│       ├── test_gemini_provider.py
│       ├── test_acli_client.py
│       └── test_git_client.py
│
├── integration/                # Tests with real (mocked) I/O
│   ├── __init__.py
│   └── test_cli.py
│
└── fixtures/                   # Test data
    ├── jira_responses/
    │   ├── valid_ticket.json
    │   └── not_found.json
    └── git/
        ├── sample_diff.txt
        └── commit_log.txt
```

---

## Testing by Layer

### 1. Domain Layer Tests

**What to test:**
- Entity creation and validation
- Pydantic model behavior
- Factory methods (e.g., `from_acli_response`)

**How to test:**
- Direct instantiation
- No mocks needed (pure logic)

```python
# tests/unit/domain/test_jira_ticket.py

import pytest
from pydantic import ValidationError
from auto_pr.domain.entities import JiraTicket


class TestJiraTicket:
    def test_create_valid_ticket(self):
        ticket = JiraTicket(
            key="TLAB-123",
            title="Fix bug",
            description="Description here",
            ticket_type="Task",
            url="https://example.atlassian.net/browse/TLAB-123",
        )
        
        assert ticket.key == "TLAB-123"
        assert ticket.title == "Fix bug"
    
    def test_invalid_key_format_raises(self):
        with pytest.raises(ValidationError):
            JiraTicket(
                key="invalid",  # Missing number
                title="Fix bug",
                description="",
                ticket_type="Task",
                url="https://example.com",
            )
    
    def test_ticket_is_immutable(self):
        ticket = JiraTicket(
            key="TLAB-123",
            title="Fix bug",
            description="",
            ticket_type="Task",
            url="https://example.com",
        )
        
        with pytest.raises(ValidationError):
            ticket.title = "New title"  # Should fail - frozen
    
    def test_from_acli_response(self):
        acli_data = {
            "key": "TLAB-123",
            "fields": {
                "summary": "Fix the bug",
                "description": {"content": [...]},
                "issuetype": {"name": "Task"},
            }
        }
        
        ticket = JiraTicket.from_acli_response(acli_data)
        
        assert ticket.key == "TLAB-123"
        assert ticket.title == "Fix the bug"
```

### 2. Infrastructure Layer Tests

**What to test:**
- CLI tool invocation
- Response parsing
- Error handling

**How to test:**
- Mock `subprocess.run`
- Use fixture files for responses

```python
# tests/unit/infrastructure/test_acli_client.py

import pytest
from unittest.mock import patch, MagicMock
from auto_pr.infrastructure.jira import AcliJiraClient
from auto_pr.domain.exceptions import JiraTicketNotFoundError


class TestAcliJiraClient:
    @pytest.fixture
    def client(self):
        return AcliJiraClient()
    
    @pytest.fixture
    def valid_response(self):
        return {
            "key": "TLAB-123",
            "fields": {
                "summary": "Test ticket",
                "description": None,
                "issuetype": {"name": "Task"},
            }
        }
    
    def test_fetch_valid_ticket(self, client, valid_response):
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=json.dumps(valid_response),
                stderr="",
            )
            
            ticket = client.fetch("TLAB-123")
            
            assert ticket.key == "TLAB-123"
            mock_run.assert_called_once()
    
    def test_fetch_not_found_raises(self, client):
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=1,
                stdout="",
                stderr="Issue not found",
            )
            
            with pytest.raises(JiraTicketNotFoundError) as exc_info:
                client.fetch("INVALID-999")
            
            assert exc_info.value.ticket == "INVALID-999"
```

### 3. Application Layer Tests

**What to test:**
- Use case orchestration
- Business logic
- Error propagation

**How to test:**
- Mock all infrastructure dependencies
- Inject mocks via constructor

```python
# tests/unit/application/test_generate_pr.py

import pytest
from unittest.mock import MagicMock
from auto_pr.application.use_cases import GeneratePRDescription
from auto_pr.domain.entities import JiraTicket, GitContext, PRDescription


class TestGeneratePRDescription:
    @pytest.fixture
    def mock_jira_client(self):
        client = MagicMock()
        client.fetch.return_value = JiraTicket(
            key="TLAB-123",
            title="Test ticket",
            description="Do something",
            ticket_type="Task",
            url="https://example.com/TLAB-123",
        )
        return client
    
    @pytest.fixture
    def mock_git_client(self):
        client = MagicMock()
        client.get_context.return_value = GitContext(
            branch="task/TLAB-123",
            commits=["feat: add feature"],
            changed_files=["src/main.py"],
            diff="+ new code",
            diff_stat="1 file changed",
        )
        return client
    
    @pytest.fixture
    def mock_ai_provider(self):
        provider = MagicMock()
        provider.generate.return_value = PRDescription(
            content="## Summary\nThis PR adds..."
        )
        return provider
    
    def test_generate_pr_success(
        self,
        mock_jira_client,
        mock_git_client,
        mock_ai_provider,
    ):
        use_case = GeneratePRDescription(
            jira_client=mock_jira_client,
            git_client=mock_git_client,
            ai_provider=mock_ai_provider,
        )
        
        result = use_case.execute("task/TLAB-123")
        
        assert "Summary" in result.content
        mock_jira_client.fetch.assert_called_once_with("TLAB-123")
        mock_git_client.get_context.assert_called_once()
        mock_ai_provider.generate.assert_called_once()
```

### 4. CLI/Integration Tests

**What to test:**
- End-to-end command execution
- Output formatting
- Exit codes

**How to test:**
- Use Typer's `CliRunner`
- Mock at infrastructure boundary

```python
# tests/integration/test_cli.py

import pytest
from typer.testing import CliRunner
from unittest.mock import patch
from auto_pr.cli.app import app


runner = CliRunner()


class TestCLI:
    def test_help_shows_options(self):
        result = runner.invoke(app, ["--help"])
        
        assert result.exit_code == 0
        assert "--gemini" in result.stdout
        assert "--copilot" in result.stdout
        assert "--agent" in result.stdout
    
    def test_version_flag(self):
        result = runner.invoke(app, ["--version"])
        
        assert result.exit_code == 0
        assert "autopr" in result.stdout
    
    @patch("auto_pr.cli.app.create_use_case")
    def test_dry_run_does_not_create_pr(self, mock_create):
        mock_use_case = MagicMock()
        mock_use_case.execute.return_value = PRDescription(content="Test")
        mock_create.return_value = mock_use_case
        
        result = runner.invoke(app, ["--dry-run"])
        
        # Should show output but not create PR
        assert "Test" in result.stdout
        mock_use_case.create_pr.assert_not_called()
```

---

## Fixtures

### Shared Fixtures (`conftest.py`)

```python
# tests/conftest.py

import pytest
import json
from pathlib import Path


FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def jira_valid_response():
    """Load valid Jira API response."""
    with open(FIXTURES_DIR / "jira_responses" / "valid_ticket.json") as f:
        return json.load(f)


@pytest.fixture
def sample_git_diff():
    """Load sample git diff."""
    with open(FIXTURES_DIR / "git" / "sample_diff.txt") as f:
        return f.read()
```

### Fixture Files

```json
// tests/fixtures/jira_responses/valid_ticket.json
{
  "key": "TLAB-123",
  "fields": {
    "summary": "Implement feature X",
    "description": {
      "content": [
        {
          "content": [{"text": "As a user, I want...", "type": "text"}],
          "type": "paragraph"
        }
      ]
    },
    "issuetype": {"name": "Story"}
  }
}
```

---

## Coverage Requirements

| Layer | Minimum Coverage |
|-------|------------------|
| Domain | 100% |
| Application | 90% |
| Infrastructure | 80% |
| CLI | 70% |
| **Overall** | **85%** |

### Running Coverage

```bash
# Run tests with coverage
pytest --cov=auto_pr --cov-report=html

# Fail if below threshold
pytest --cov=auto_pr --cov-fail-under=85
```

---

## Test Naming Convention

```python
def test_<method>_<scenario>_<expected_result>():
    pass

# Examples:
def test_fetch_valid_ticket_returns_entity():
def test_fetch_not_found_raises_exception():
def test_generate_empty_diff_uses_fallback():
```

---

## Rules Summary

| Rule | Description |
|------|-------------|
| **Test Behavior** | Test what it does, not how |
| **Mock at Boundaries** | Mock infrastructure in app tests |
| **No Mocks in Domain** | Domain tests are pure |
| **Use Fixtures** | Shared test data in `conftest.py` |
| **Descriptive Names** | `test_what_when_then` pattern |
| **One Assert Focus** | One logical assertion per test |
| **Fast Unit Tests** | No I/O in unit tests |
