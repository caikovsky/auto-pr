"""Cursor Agent AI provider."""

from auto_pr.infrastructure.ai.base import BaseAIProvider


class AgentProvider(BaseAIProvider):
    """Cursor Agent CLI provider."""

    @property
    def cli_command(self) -> str:
        return "agent"

    @property
    def cli_args(self) -> list[str]:
        return []
