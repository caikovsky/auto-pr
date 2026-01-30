"""Gemini AI provider."""

from auto_pr.infrastructure.ai.base import BaseAIProvider


class GeminiProvider(BaseAIProvider):
    """Google Gemini CLI provider."""

    @property
    def cli_command(self) -> str:
        return "gemini"

    @property
    def cli_args(self) -> list[str]:
        return ["-o", "text"]
