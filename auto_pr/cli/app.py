"""CLI entry point for auto-pr."""

from typing import Annotated

import typer
from rich.console import Console

__version__ = "2.0.0"

app = typer.Typer(name="auto-pr", help="AI-powered PR creation tool")
console = Console()


@app.command()
def main(
    dry_run: Annotated[bool, typer.Option("--dry-run", "-n", help="Preview without creating PR")] = False,
    gemini: Annotated[bool, typer.Option("--gemini", help="Use Gemini AI")] = False,
    copilot: Annotated[bool, typer.Option("--copilot", help="Use GitHub Copilot")] = False,
    agent: Annotated[bool, typer.Option("--agent", help="Use Cursor Agent")] = False,
    test: Annotated[bool, typer.Option("--test", help="Compare all AI providers")] = False,
    verbose: Annotated[bool, typer.Option("--verbose", "-v", help="Verbose output")] = False,
) -> None:
    """Generate and create a PR with AI-powered description."""
    console.print(f"[bold]auto-pr[/bold] v{__version__}")
    console.print(f"[dim]Options: dry_run={dry_run}, gemini={gemini}, copilot={copilot}, agent={agent}, test={test}[/dim]")
    console.print("[yellow]Migration in progress - full implementation in next phases[/yellow]")


if __name__ == "__main__":
    app()
