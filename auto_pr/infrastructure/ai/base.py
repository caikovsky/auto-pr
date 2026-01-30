"""Base AI provider with shared logic."""

from abc import abstractmethod

from auto_pr.domain.entities import PRDescription
from auto_pr.domain.exceptions import AIGenerationError
from auto_pr.domain.interfaces import AIProvider
from auto_pr.infrastructure.subprocess_runner import (
    CommandResult,
    ToolExecutionError,
    check_tool_exists,
    run_command,
)


class BaseAIProvider(AIProvider):
    """Base class for AI CLI providers."""

    @property
    @abstractmethod
    def cli_command(self) -> str:
        """The CLI command name."""
        ...

    @property
    @abstractmethod
    def cli_args(self) -> list[str]:
        """Arguments to pass to the CLI."""
        ...

    @property
    def name(self) -> str:
        """Provider name for display."""
        return self.cli_command

    def is_available(self) -> bool:
        """Check if this provider's CLI is installed."""
        return check_tool_exists(self.cli_command)

    def generate(self, prompt: str) -> PRDescription:
        """Generate PR description from prompt."""
        try:
            result = self._call_cli(prompt)
            content = self._parse_response(result)

            if not content.strip():
                raise AIGenerationError(self.name, "Empty response")

            return PRDescription(content=content, ai_provider=self.name)

        except ToolExecutionError as e:
            raise AIGenerationError(self.name, e.stderr) from e

    def _call_cli(self, prompt: str) -> CommandResult:
        """Call the AI CLI with the prompt."""
        args = [self.cli_command, *self.cli_args]
        return run_command(args, input_text=prompt, timeout=120)

    def _parse_response(self, result: CommandResult) -> str:
        """Parse the CLI response. Override if needed."""
        return result.stdout.strip()
