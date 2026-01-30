"""GitHub client using gh CLI."""

from pathlib import Path

from auto_pr.domain.exceptions import (
    GitHubAuthenticationError,
    PRCreationError,
    ToolExecutionError,
)
from auto_pr.domain.interfaces import PRClient
from auto_pr.infrastructure.subprocess_runner import run_command


class GhPRClient(PRClient):
    """GitHub PR client using gh CLI."""

    PR_TEMPLATE_PATHS = [
        ".github/pull_request_template.md",
        ".github/PULL_REQUEST_TEMPLATE.md",
        "pull_request_template.md",
        "PULL_REQUEST_TEMPLATE.md",
    ]

    def get_pr_template(self) -> str | None:
        """Get the repository's PR template if it exists."""
        # Get repo root
        try:
            result = run_command(["git", "rev-parse", "--show-toplevel"])
            repo_root = Path(result.stdout.strip())
        except ToolExecutionError:
            return None

        # Search for template
        for template_path in self.PR_TEMPLATE_PATHS:
            full_path = repo_root / template_path
            if full_path.exists():
                return full_path.read_text()

        return None

    def create_pr(
        self,
        title: str,
        body: str,
        base_branch: str = "main",
        draft: bool = False,
    ) -> str:
        """Create a pull request."""
        args = [
            "gh", "pr", "create",
            "--title", title,
            "--body", body,
            "--base", base_branch,
        ]

        if draft:
            args.append("--draft")

        try:
            result = run_command(args, timeout=60)
            # gh pr create outputs the PR URL
            return result.stdout.strip()

        except ToolExecutionError as e:
            self._handle_error(e)
            raise  # Re-raise if not handled

    def _handle_error(self, error: ToolExecutionError) -> None:
        """Convert generic tool errors to specific GitHub errors."""
        stderr_lower = error.stderr.lower()

        if "auth" in stderr_lower or "login" in stderr_lower:
            raise GitHubAuthenticationError() from error

        if "already exists" in stderr_lower:
            raise PRCreationError("A pull request already exists for this branch") from error

        if "no commits" in stderr_lower:
            raise PRCreationError("No commits between base and head branch") from error

        # Generic PR creation error
        raise PRCreationError(error.stderr) from error
