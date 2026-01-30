"""Git client interface."""

from abc import ABC, abstractmethod

from auto_pr.domain.entities import GitContext


class GitClient(ABC):
    """Interface for Git operations."""

    @abstractmethod
    def get_current_branch(self) -> str:
        """Get the current branch name.

        Raises:
            NotAGitRepositoryError: If not in a git repository.
        """
        ...

    @abstractmethod
    def get_context(self, base_branch: str = "main") -> GitContext:
        """Get full git context for PR generation.

        Args:
            base_branch: The target branch for comparison.

        Returns:
            GitContext with branch, commits, files, and diff.

        Raises:
            NotAGitRepositoryError: If not in a git repository.
        """
        ...

    @abstractmethod
    def extract_ticket_key(self, branch: str) -> str | None:
        """Extract Jira ticket key from branch name.

        Args:
            branch: Branch name (e.g., "task/TLAB-123-description").

        Returns:
            Ticket key (e.g., "TLAB-123") or None if not found.
        """
        ...
