"""PR client interface."""

from abc import ABC, abstractmethod

from auto_pr.domain.entities import ExistingPR


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
    def find_pr_for_branch(self, branch: str) -> ExistingPR | None:
        """Find an existing PR for the given branch.

        Args:
            branch: The head branch name.

        Returns:
            ExistingPR if found, None otherwise.
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

    @abstractmethod
    def update_pr(
        self,
        pr_number: int,
        title: str,
        body: str,
    ) -> str:
        """Update an existing pull request.

        Args:
            pr_number: PR number to update.
            title: New PR title.
            body: New PR description body.

        Returns:
            URL of the updated PR.

        Raises:
            GitHubAuthenticationError: If not authenticated.
            PRCreationError: If PR update fails.
        """
        ...
