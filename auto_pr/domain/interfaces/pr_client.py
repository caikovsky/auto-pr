"""PR client interface."""

from abc import ABC, abstractmethod


class PRClient(ABC):
    """Interface for PR creation (GitHub)."""

    @abstractmethod
    def get_pr_template(self) -> str | None:
        """Get the repository's PR template if it exists.

        Returns:
            Template content or None if no template exists.
        """
        ...

    @abstractmethod
    def create_pr(
        self,
        title: str,
        body: str,
        base_branch: str = "main",
        draft: bool = False,
    ) -> str:
        """Create a pull request.

        Args:
            title: PR title.
            body: PR description body.
            base_branch: Target branch.
            draft: Create as draft PR.

        Returns:
            URL of the created PR.

        Raises:
            GitHubAuthenticationError: If not authenticated.
            PRCreationError: If PR creation fails.
        """
        ...
