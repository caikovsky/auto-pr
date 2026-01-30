"""Jira client interface."""

from abc import ABC, abstractmethod

from auto_pr.domain.entities import JiraTicket


class JiraClient(ABC):
    """Interface for Jira client (read-only)."""

    @abstractmethod
    def fetch(self, ticket_key: str) -> JiraTicket:
        """Fetch a Jira ticket by key.

        Args:
            ticket_key: The Jira ticket key (e.g., "TLAB-123").

        Returns:
            The fetched JiraTicket entity.

        Raises:
            JiraTicketNotFoundError: If ticket doesn't exist.
            JiraAuthenticationError: If not authenticated.
        """
        ...
