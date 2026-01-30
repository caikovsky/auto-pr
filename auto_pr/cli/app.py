"""CLI entry point for auto-pr."""

from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console
from rich.panel import Panel

from auto_pr.application import (
    AISelector,
    CompareAIOutputs,
    CreatePullRequest,
    GeneratePRDescription,
    PromptBuilder,
)
from auto_pr.config import load_settings
from auto_pr.domain.exceptions import AutoPRError
from auto_pr.infrastructure import (
    AcliJiraClient,
    GhPRClient,
    GitClientImpl,
)

__version__ = "2.0.0"

app = typer.Typer(name="autopr", help="AI-powered PR creation tool")
console = Console()


def _get_ai_choice(gemini: bool, copilot: bool, agent: bool) -> str | None:
    """Determine AI provider from flags."""
    if gemini:
        return "gemini"
    if copilot:
        return "copilot"
    if agent:
        return "agent"
    return None


@app.command()
def main(
    dry_run: Annotated[bool, typer.Option("--dry-run", "-n", help="Preview without creating PR")] = False,
    draft: Annotated[bool, typer.Option("--draft", "-d", help="Create as draft PR")] = False,
    base: Annotated[str | None, typer.Option("--base", "-b", help="Base branch for PR")] = None,
    gemini: Annotated[bool, typer.Option("--gemini", help="Use Gemini AI")] = False,
    copilot: Annotated[bool, typer.Option("--copilot", help="Use GitHub Copilot")] = False,
    agent: Annotated[bool, typer.Option("--agent", help="Use Cursor Agent")] = False,
    test: Annotated[bool, typer.Option("--test", help="Compare all AI providers")] = False,
    test_dir: Annotated[Path | None, typer.Option("--test-dir", help="Output directory for --test")] = None,
    verbose: Annotated[bool, typer.Option("--verbose", "-v", help="Verbose output")] = False,
) -> None:
    """Generate and create a PR with AI-powered description."""
    try:
        # Load config
        settings = load_settings()

        # Use config defaults if not specified
        base_branch = base or settings.base_branch
        ai_choice = _get_ai_choice(gemini, copilot, agent) or (
            None if settings.ai_provider == "auto" else settings.ai_provider
        )

        # Comparison mode
        if test:
            _run_comparison(base_branch, test_dir, verbose)
            return

        # Normal mode
        _run_generate(base_branch, ai_choice, dry_run, draft, verbose)

    except AutoPRError as e:
        console.print(f"[red]Error:[/red] {e.message}")
        if e.hint:
            console.print(f"[yellow]Hint:[/yellow] {e.hint}")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Unexpected error:[/red] {e}")
        raise typer.Exit(2)


def _run_generate(
    base: str,
    ai_choice: str | None,
    dry_run: bool,
    draft: bool,
    verbose: bool,
) -> None:
    """Run the main PR generation flow."""
    # Build dependencies
    git_client = GitClientImpl()
    jira_client = AcliJiraClient()
    pr_client = GhPRClient()
    ai_selector = AISelector()
    prompt_builder = PromptBuilder()

    # Get AI provider
    ai_provider = ai_selector.get_provider(ai_choice)
    console.print(f"[dim]Using AI provider:[/dim] [cyan]{ai_provider.name}[/cyan]")

    # Create use case
    generate_uc = GeneratePRDescription(
        git_client=git_client,
        jira_client=jira_client,
        pr_client=pr_client,
        ai_provider=ai_provider,
        prompt_builder=prompt_builder,
    )

    # Execute
    console.print("[dim]Generating PR description...[/dim]")
    result = generate_uc.execute(base_branch=base)

    # Show result
    console.print()
    console.print(Panel(f"[bold]{result.title}[/bold]", title="PR Title"))
    console.print()

    if verbose:
        console.print(Panel(result.description.content, title="PR Description"))
    else:
        # Show truncated preview
        preview = result.description.content[:500]
        if len(result.description.content) > 500:
            preview += "\n\n[dim]... (truncated, use --verbose to see full)[/dim]"
        console.print(Panel(preview, title="PR Description Preview"))

    console.print()
    if result.ticket:
        console.print(f"[dim]Ticket:[/dim] {result.ticket.key}")
    elif result.ticket_error:
        console.print(f"[yellow]Warning:[/yellow] {result.ticket_error}")
        console.print(f"[dim]Ticket:[/dim] N/A (continuing without ticket)")
    else:
        console.print(f"[dim]Ticket:[/dim] N/A (no ticket in branch name)")
    console.print(f"[dim]Commits:[/dim] {result.context.commit_count}")
    console.print(f"[dim]Files:[/dim] {result.context.file_count}")

    # Create PR or dry run
    if dry_run:
        console.print()
        console.print("[yellow]Dry run mode - PR not created[/yellow]")
    else:
        console.print()
        console.print("[dim]Creating PR...[/dim]")

        create_uc = CreatePullRequest(pr_client=pr_client)
        pr_result = create_uc.execute(result, draft=draft)

        console.print()
        console.print(f"[green]✓ PR created:[/green] {pr_result.url}")
        if pr_result.draft:
            console.print("[dim](created as draft)[/dim]")


def _run_comparison(base: str, output_dir: Path | None, verbose: bool) -> None:
    """Run the AI comparison flow."""
    # Build dependencies
    git_client = GitClientImpl()
    jira_client = AcliJiraClient()
    pr_client = GhPRClient()
    ai_selector = AISelector()
    prompt_builder = PromptBuilder()

    # Create use case
    compare_uc = CompareAIOutputs(
        git_client=git_client,
        jira_client=jira_client,
        pr_client=pr_client,
        ai_selector=ai_selector,
        prompt_builder=prompt_builder,
    )

    # Default output dir
    if output_dir is None:
        output_dir = Path("./ai-comparison")

    console.print(f"[dim]Running AI comparison...[/dim]")
    console.print(f"[dim]Output directory:[/dim] {output_dir}")
    console.print()

    # Execute
    result = compare_uc.execute(base_branch=base, output_dir=output_dir)

    # Show results
    console.print(Panel(
        f"Branch: {result.context.branch}\n"
        f"Ticket: {result.ticket.key if result.ticket else 'N/A'}",
        title="Context",
    ))
    console.print()

    for r in result.results:
        if r.success:
            console.print(f"[green]✓[/green] {r.provider}: Success")
        else:
            console.print(f"[red]✗[/red] {r.provider}: {r.error}")

    console.print()
    console.print(f"[dim]Results saved to:[/dim] {output_dir}")
    console.print(f"[dim]Summary:[/dim] {result.successful_count} succeeded, {result.failed_count} failed")


if __name__ == "__main__":
    app()
