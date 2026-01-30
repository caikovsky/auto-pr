"""Git client implementation."""

import re

from auto_pr.domain.entities import GitContext
from auto_pr.domain.exceptions import NotAGitRepositoryError
from auto_pr.domain.interfaces import GitClient
from auto_pr.infrastructure.subprocess_runner import run_command, CommandResult


class GitClientImpl(GitClient):
    """Git client using git CLI."""

    TICKET_PATTERN = re.compile(r"([A-Z]+-\d+)")

    def get_current_branch(self) -> str:
        """Get the current branch name."""
        result = self._run_git(["branch", "--show-current"])
        branch = result.stdout.strip()

        if not branch:
            raise NotAGitRepositoryError()

        return branch

    def get_context(self, base_branch: str = "main") -> GitContext:
        """Get full git context for PR generation."""
        branch = self.get_current_branch()

        # Get commits
        commits_result = self._run_git(
            ["log", f"{base_branch}..HEAD", "--oneline", "--no-decorate"],
            check=False,
        )
        commits = [
            line.split(" ", 1)[1] if " " in line else line
            for line in commits_result.stdout.strip().split("\n")
            if line.strip()
        ]

        # Get changed files
        files_result = self._run_git(
            ["diff", "--name-only", base_branch],
            check=False,
        )
        changed_files = [f for f in files_result.stdout.strip().split("\n") if f.strip()]

        # Get diff content (limited)
        diff_result = self._run_git(
            ["diff", base_branch, "--no-color"],
            check=False,
        )
        diff = self._truncate_diff(diff_result.stdout, max_lines=800)

        # Get diff stat
        stat_result = self._run_git(
            ["diff", "--stat", base_branch],
            check=False,
        )
        diff_stat = stat_result.stdout.strip()

        return GitContext(
            branch=branch,
            base_branch=base_branch,
            commits=commits,
            changed_files=changed_files,
            diff=diff,
            diff_stat=diff_stat,
        )

    def extract_ticket_key(self, branch: str) -> str | None:
        """Extract Jira ticket key from branch name."""
        match = self.TICKET_PATTERN.search(branch)
        return match.group(1) if match else None

    def _run_git(self, args: list[str], *, check: bool = True) -> CommandResult:
        """Run a git command."""
        return run_command(["git", *args], check=check)

    def _truncate_diff(self, diff: str, max_lines: int) -> str:
        """Truncate diff to max lines."""
        lines = diff.split("\n")
        if len(lines) <= max_lines:
            return diff
        return "\n".join(lines[:max_lines]) + f"\n\n... (truncated, {len(lines) - max_lines} more lines)"
