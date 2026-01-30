"""Domain layer - core entities, interfaces, and exceptions."""

from auto_pr.domain.entities import GitContext, JiraTicket, PRDescription
from auto_pr.domain.exceptions import (
    AIError,
    AIGenerationError,
    AIProviderNotFoundError,
    AutoPRError,
    BranchParseError,
    ConfigurationError,
    GitError,
    GitHubAuthenticationError,
    GitHubError,
    JiraAuthenticationError,
    JiraError,
    JiraTicketNotFoundError,
    NotAGitRepositoryError,
    PRCreationError,
    ToolExecutionError,
    ToolNotFoundError,
)
from auto_pr.domain.interfaces import AIProvider, GitClient, JiraClient, PRClient

__all__ = [
    # Entities
    "GitContext",
    "JiraTicket",
    "PRDescription",
    # Interfaces
    "AIProvider",
    "GitClient",
    "JiraClient",
    "PRClient",
    # Exceptions
    "AutoPRError",
    "ConfigurationError",
    "ToolNotFoundError",
    "ToolExecutionError",
    "JiraError",
    "JiraTicketNotFoundError",
    "JiraAuthenticationError",
    "GitError",
    "NotAGitRepositoryError",
    "BranchParseError",
    "AIError",
    "AIProviderNotFoundError",
    "AIGenerationError",
    "GitHubError",
    "GitHubAuthenticationError",
    "PRCreationError",
]
