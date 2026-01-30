"""GitHub Copilot AI provider."""

from auto_pr.infrastructure.ai.base import BaseAIProvider


class CopilotProvider(BaseAIProvider):
    """GitHub Copilot CLI provider."""

    @property
    def cli_command(self) -> str:
        return "copilot"

    @property
    def cli_args(self) -> list[str]:
        return []
