"""Domain exceptions - custom error hierarchy."""


class AutoPRError(Exception):
    """Base exception for all auto-pr errors."""

    def __init__(self, message: str, hint: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.hint = hint


# Configuration errors
class ConfigurationError(AutoPRError):
    """Invalid or missing configuration."""


# External tool errors
class ToolNotFoundError(AutoPRError):
    """Required CLI tool is not installed."""

    def __init__(self, tool: str) -> None:
        super().__init__(
            f"Required tool not found: {tool}",
            hint=f"Install {tool} and ensure it's in your PATH",
        )
        self.tool = tool


class ToolExecutionError(AutoPRError):
    """CLI tool execution failed."""

    def __init__(self, tool: str, exit_code: int, stderr: str = "") -> None:
        super().__init__(
            f"{tool} failed with exit code {exit_code}",
            hint=f"Check if {tool} is working: {tool} --help",
        )
        self.tool = tool
        self.exit_code = exit_code
        self.stderr = stderr


# Jira errors
class JiraError(AutoPRError):
    """Jira-related errors."""


class JiraTicketNotFoundError(JiraError):
    """Jira ticket does not exist."""

    def __init__(self, ticket: str) -> None:
        super().__init__(
            f"Jira ticket not found: {ticket}",
            hint="Check the ticket key and your Jira permissions",
        )
        self.ticket = ticket


class JiraAuthenticationError(JiraError):
    """Not authenticated with Jira."""

    def __init__(self) -> None:
        super().__init__(
            "Not authenticated with Jira",
            hint="Run: acli auth login",
        )


# Git errors
class GitError(AutoPRError):
    """Git-related errors."""


class NotAGitRepositoryError(GitError):
    """Not in a git repository."""

    def __init__(self) -> None:
        super().__init__(
            "Not in a git repository",
            hint="Run this command from inside a git repository",
        )


class BranchParseError(GitError):
    """Cannot parse Jira ticket from branch name."""

    def __init__(self, branch: str) -> None:
        super().__init__(
            f"Cannot extract Jira ticket from branch: {branch}",
            hint="Use format: task/PROJ-123 or feature/PROJ-123-description",
        )
        self.branch = branch


# AI errors
class AIError(AutoPRError):
    """AI provider errors."""


class AIProviderNotFoundError(AIError):
    """No AI CLI tool installed."""

    def __init__(self, requested: str | None = None) -> None:
        if requested:
            msg = f"AI CLI not found: {requested}"
            hint = f"Install {requested} or use a different provider"
        else:
            msg = "No AI CLI tool found"
            hint = "Install one of: gemini, copilot, agent"
        super().__init__(msg, hint=hint)
        self.requested = requested


class AIGenerationError(AIError):
    """AI failed to generate content."""

    def __init__(self, provider: str, reason: str = "") -> None:
        msg = f"AI generation failed ({provider})"
        if reason:
            msg += f": {reason}"
        super().__init__(msg, hint="Try again or use a different AI provider")
        self.provider = provider
        self.reason = reason


# GitHub errors
class GitHubError(AutoPRError):
    """GitHub-related errors."""


class GitHubAuthenticationError(GitHubError):
    """Not authenticated with GitHub."""

    def __init__(self) -> None:
        super().__init__(
            "Not authenticated with GitHub",
            hint="Run: gh auth login",
        )


class PRCreationError(GitHubError):
    """Failed to create pull request."""

    def __init__(self, reason: str = "") -> None:
        msg = "Failed to create pull request"
        if reason:
            msg += f": {reason}"
        super().__init__(msg, hint="Check gh auth status and repository permissions")
        self.reason = reason
