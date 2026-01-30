"""Jira client using Atlassian CLI (acli)."""

import json

from auto_pr.domain.entities import JiraTicket
from auto_pr.domain.exceptions import (
    JiraAuthenticationError,
    JiraTicketNotFoundError,
    ToolExecutionError,
)
from auto_pr.domain.interfaces import JiraClient
from auto_pr.infrastructure.subprocess_runner import run_command


class AcliJiraClient(JiraClient):
    """Jira client using acli CLI (read-only)."""

    def fetch(self, ticket_key: str) -> JiraTicket:
        """Fetch a Jira ticket by key."""
        try:
            result = run_command(
                ["acli", "jira", "workitem", "view", ticket_key, "--json"],
                timeout=30,
            )
        except ToolExecutionError as e:
            self._handle_error(e, ticket_key)
            raise  # Re-raise if not handled

        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError as e:
            raise ToolExecutionError(
                tool="acli",
                exit_code=0,
                stderr=f"Invalid JSON response: {e}",
            ) from e

        return JiraTicket.from_acli_response(data)

    def _handle_error(self, error: ToolExecutionError, ticket_key: str) -> None:
        """Convert generic tool errors to specific Jira errors."""
        stderr_lower = error.stderr.lower()

        if "not found" in stderr_lower or "does not exist" in stderr_lower:
            raise JiraTicketNotFoundError(ticket_key) from error

        if "auth" in stderr_lower or "login" in stderr_lower or "unauthorized" in stderr_lower:
            raise JiraAuthenticationError() from error
