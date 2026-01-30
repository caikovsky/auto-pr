"""Create PR use case."""

from dataclasses import dataclass

from auto_pr.domain.interfaces import PRClient
from auto_pr.application.use_cases.generate_pr import GeneratePRResult


@dataclass
class CreatePRResult:
    """Result of PR creation."""

    url: str
    title: str
    draft: bool


class CreatePullRequest:
    """Use case: Create a pull request on GitHub."""

    def __init__(self, pr_client: PRClient) -> None:
        self._pr = pr_client

    def execute(
        self,
        generated: GeneratePRResult,
        draft: bool = False,
    ) -> CreatePRResult:
        """Execute the use case.

        Args:
            generated: Result from GeneratePRDescription use case.
            draft: Create as draft PR.

        Returns:
            CreatePRResult with PR URL.

        Raises:
            GitHubAuthenticationError: If not authenticated.
            PRCreationError: If PR creation fails.
        """
        url = self._pr.create_pr(
            title=generated.title,
            body=generated.description.content,
            base_branch=generated.context.base_branch,
            draft=draft,
        )

        return CreatePRResult(
            url=url,
            title=generated.title,
            draft=draft,
        )
