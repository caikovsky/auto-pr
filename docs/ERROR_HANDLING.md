# Error Handling Guidelines

> **Principle**: Use custom exceptions with clear hierarchy. Catch at boundaries.

---

## Approach: Custom Exceptions

We use **custom exceptions** (not Result types) because:
- More Pythonic and familiar
- Typer integrates well with exceptions
- Simpler to implement and understand
- Stack traces help with debugging

---

## Exception Hierarchy

```python
# auto_pr/domain/exceptions.py

class AutoPRError(Exception):
    """Base exception for all autopr errors."""
    
    def __init__(self, message: str, hint: str | None = None):
        super().__init__(message)
        self.message = message
        self.hint = hint  # Actionable suggestion for user


# Configuration errors
class ConfigurationError(AutoPRError):
    """Invalid or missing configuration."""
    pass


# External tool errors
class ToolNotFoundError(AutoPRError):
    """Required CLI tool is not installed."""
    pass

class ToolExecutionError(AutoPRError):
    """CLI tool execution failed."""
    
    def __init__(self, message: str, tool: str, exit_code: int, stderr: str = ""):
        super().__init__(message, hint=f"Check if {tool} is working: {tool} --help")
        self.tool = tool
        self.exit_code = exit_code
        self.stderr = stderr


# Jira errors
class JiraError(AutoPRError):
    """Jira-related errors."""
    pass

class JiraTicketNotFoundError(JiraError):
    """Jira ticket does not exist."""
    
    def __init__(self, ticket: str):
        super().__init__(
            f"Jira ticket not found: {ticket}",
            hint="Check the ticket key and your Jira permissions"
        )
        self.ticket = ticket

class JiraAuthenticationError(JiraError):
    """Not authenticated with Jira."""
    
    def __init__(self):
        super().__init__(
            "Not authenticated with Jira",
            hint="Run: acli auth login"
        )


# Git errors
class GitError(AutoPRError):
    """Git-related errors."""
    pass

class NotAGitRepositoryError(GitError):
    """Not in a git repository."""
    
    def __init__(self):
        super().__init__(
            "Not in a git repository",
            hint="Run this command from inside a git repository"
        )

class BranchParseError(GitError):
    """Cannot parse Jira ticket from branch name."""
    
    def __init__(self, branch: str):
        super().__init__(
            f"Cannot extract Jira ticket from branch: {branch}",
            hint="Use format: task/PROJ-123 or feature/PROJ-123-description"
        )
        self.branch = branch


# AI errors
class AIError(AutoPRError):
    """AI provider errors."""
    pass

class AIProviderNotFoundError(AIError):
    """No AI CLI tool installed."""
    
    def __init__(self, requested: str | None = None):
        if requested:
            msg = f"AI CLI not found: {requested}"
            hint = f"Install {requested} or use a different provider"
        else:
            msg = "No AI CLI tool found"
            hint = "Install one of: gemini, copilot, agent"
        super().__init__(msg, hint=hint)

class AIGenerationError(AIError):
    """AI failed to generate content."""
    pass


# GitHub errors
class GitHubError(AutoPRError):
    """GitHub-related errors."""
    pass

class GitHubAuthenticationError(GitHubError):
    """Not authenticated with GitHub."""
    
    def __init__(self):
        super().__init__(
            "Not authenticated with GitHub",
            hint="Run: gh auth login"
        )

class PRCreationError(GitHubError):
    """Failed to create pull request."""
    pass
```

---

## Exception Hierarchy Diagram

```
AutoPRError (base)
├── ConfigurationError
├── ToolNotFoundError
├── ToolExecutionError
├── JiraError
│   ├── JiraTicketNotFoundError
│   └── JiraAuthenticationError
├── GitError
│   ├── NotAGitRepositoryError
│   └── BranchParseError
├── AIError
│   ├── AIProviderNotFoundError
│   └── AIGenerationError
└── GitHubError
    ├── GitHubAuthenticationError
    └── PRCreationError
```

---

## Where to Raise Exceptions

### Infrastructure Layer

Raise exceptions when external operations fail:

```python
# auto_pr/infrastructure/jira/acli_client.py

class AcliJiraClient(JiraClient):
    def fetch(self, ticket_key: str) -> JiraTicket:
        result = subprocess.run(
            ["acli", "jira", "workitem", "view", ticket_key, "--json"],
            capture_output=True,
            text=True,
        )
        
        if result.returncode != 0:
            if "not found" in result.stderr.lower():
                raise JiraTicketNotFoundError(ticket_key)
            if "authentication" in result.stderr.lower():
                raise JiraAuthenticationError()
            raise ToolExecutionError(
                f"acli failed: {result.stderr}",
                tool="acli",
                exit_code=result.returncode,
                stderr=result.stderr,
            )
        
        return JiraTicket.from_acli_response(json.loads(result.stdout))
```

### Application Layer

Let exceptions propagate or wrap with context:

```python
# auto_pr/application/use_cases/generate_pr.py

class GeneratePRDescription:
    def execute(self, branch: str) -> PRDescription:
        ticket_key = self._extract_ticket(branch)
        if not ticket_key:
            raise BranchParseError(branch)
        
        # Let JiraTicketNotFoundError propagate
        ticket = self._jira.fetch(ticket_key)
        
        context = self._git.get_context()
        prompt = self._prompt_builder.build(ticket, context)
        
        # Let AIGenerationError propagate
        return self._ai.generate(prompt)
```

---

## Where to Catch Exceptions

### CLI Layer Only

Catch and handle exceptions at the CLI boundary:

```python
# auto_pr/cli/app.py

from rich.console import Console
from auto_pr.domain.exceptions import AutoPRError

console = Console()

@app.command()
def main(...):
    try:
        use_case = create_use_case(ai_choice)
        result = use_case.execute(branch)
        display_result(result)
    except AutoPRError as e:
        console.print(f"[red]Error:[/red] {e.message}")
        if e.hint:
            console.print(f"[yellow]Hint:[/yellow] {e.hint}")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Unexpected error:[/red] {e}")
        raise typer.Exit(2)
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Known error (AutoPRError) |
| 2 | Unexpected error |

---

## Rules Summary

| Rule | Description |
|------|-------------|
| **Custom Exceptions** | All errors inherit from `AutoPRError` |
| **Hints** | Provide actionable hints for users |
| **Raise in Infrastructure** | When external operations fail |
| **Propagate in Application** | Let exceptions bubble up |
| **Catch in CLI** | Handle and display at boundary |
| **No Silent Failures** | Always raise or log, never swallow |
| **Specific Exceptions** | Use specific types, not generic `Exception` |
