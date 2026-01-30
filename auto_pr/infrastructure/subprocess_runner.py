"""Subprocess runner with consistent error handling."""

import shutil
import subprocess
from dataclasses import dataclass

from auto_pr.domain.exceptions import ToolExecutionError, ToolNotFoundError


@dataclass(frozen=True)
class CommandResult:
    """Result of a subprocess command."""

    stdout: str
    stderr: str
    return_code: int

    @property
    def success(self) -> bool:
        """Check if command succeeded."""
        return self.return_code == 0


def check_tool_exists(tool: str) -> bool:
    """Check if a CLI tool is available in PATH."""
    return shutil.which(tool) is not None


def run_command(
    args: list[str],
    *,
    check: bool = True,
    capture_output: bool = True,
    input_text: str | None = None,
    timeout: int | None = 60,
) -> CommandResult:
    """Run a subprocess command with error handling.

    Args:
        args: Command and arguments.
        check: Raise ToolExecutionError if command fails.
        capture_output: Capture stdout/stderr.
        input_text: Text to send to stdin.
        timeout: Timeout in seconds.

    Returns:
        CommandResult with stdout, stderr, and return code.

    Raises:
        ToolNotFoundError: If the tool is not installed.
        ToolExecutionError: If check=True and command fails.
    """
    tool = args[0]

    if not check_tool_exists(tool):
        raise ToolNotFoundError(tool)

    try:
        result = subprocess.run(
            args,
            capture_output=capture_output,
            text=True,
            input=input_text,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        raise ToolExecutionError(
            tool=tool,
            exit_code=-1,
            stderr=f"Command timed out after {timeout}s",
        ) from e

    cmd_result = CommandResult(
        stdout=result.stdout or "",
        stderr=result.stderr or "",
        return_code=result.returncode,
    )

    if check and not cmd_result.success:
        raise ToolExecutionError(
            tool=tool,
            exit_code=cmd_result.return_code,
            stderr=cmd_result.stderr,
        )

    return cmd_result
