"""Compare AI outputs use case."""

from dataclasses import dataclass, field
from pathlib import Path

from auto_pr.domain.entities import GitContext, JiraTicket, PRDescription
from auto_pr.domain.exceptions import BranchParseError
from auto_pr.domain.interfaces import AIProvider, GitClient, JiraClient, PRClient
from auto_pr.application.services.ai_selector import AISelector
from auto_pr.application.services.prompt_builder import PromptBuilder


@dataclass
class AIComparisonResult:
    """Result from a single AI provider."""

    provider: str
    description: PRDescription | None
    error: str | None = None

    @property
    def success(self) -> bool:
        return self.description is not None


@dataclass
class CompareAIResult:
    """Result of comparing multiple AI providers."""

    ticket: JiraTicket | None
    context: GitContext
    results: list[AIComparisonResult] = field(default_factory=list)

    @property
    def successful_count(self) -> int:
        return sum(1 for r in self.results if r.success)

    @property
    def failed_count(self) -> int:
        return sum(1 for r in self.results if not r.success)


class CompareAIOutputs:
    """Use case: Compare outputs from multiple AI providers."""

    def __init__(
        self,
        git_client: GitClient,
        jira_client: JiraClient,
        pr_client: PRClient,
        ai_selector: AISelector,
        prompt_builder: PromptBuilder,
    ) -> None:
        self._git = git_client
        self._jira = jira_client
        self._pr = pr_client
        self._ai_selector = ai_selector
        self._prompt = prompt_builder

    def execute(
        self,
        base_branch: str = "main",
        output_dir: Path | None = None,
    ) -> CompareAIResult:
        """Execute the comparison.

        Args:
            base_branch: Target branch for the PR.
            output_dir: Directory to save results (optional).

        Returns:
            CompareAIResult with results from all providers.
        """
        # Get git context
        context = self._git.get_context(base_branch)

        # Extract and fetch Jira ticket
        ticket: JiraTicket | None = None
        ticket_key = self._git.extract_ticket_key(context.branch)
        if ticket_key:
            try:
                ticket = self._jira.fetch(ticket_key)
            except Exception:
                pass  # Continue without ticket

        # Get PR template
        template = self._pr.get_pr_template()

        # Build prompt
        prompt = self._prompt.build(ticket, context, template)

        # Get all available providers
        providers = self._ai_selector.get_all_available()

        # Run each provider
        comparison = CompareAIResult(ticket=ticket, context=context)

        for provider in providers:
            result = self._run_provider(provider, prompt)
            comparison.results.append(result)

        # Save results if output_dir specified
        if output_dir:
            self._save_results(comparison, output_dir)

        return comparison

    def _run_provider(self, provider: AIProvider, prompt: str) -> AIComparisonResult:
        """Run a single provider and capture result or error."""
        try:
            description = provider.generate(prompt)
            return AIComparisonResult(
                provider=provider.name,
                description=description,
            )
        except Exception as e:
            return AIComparisonResult(
                provider=provider.name,
                description=None,
                error=str(e),
            )

    def _save_results(self, comparison: CompareAIResult, output_dir: Path) -> None:
        """Save comparison results to files."""
        output_dir.mkdir(parents=True, exist_ok=True)

        # Save each provider's output
        for result in comparison.results:
            filename = f"{result.provider}.md"
            filepath = output_dir / filename

            if result.success and result.description:
                filepath.write_text(result.description.content)
            else:
                filepath.write_text(f"# Error\n\n{result.error}")

        # Save summary
        summary_path = output_dir / "summary.md"
        summary_lines = [
            "# AI Comparison Summary",
            "",
            f"Branch: {comparison.context.branch}",
            f"Ticket: {comparison.ticket.key if comparison.ticket else 'N/A'}",
            "",
            "## Results",
            "",
        ]

        for result in comparison.results:
            status = "✓" if result.success else "✗"
            summary_lines.append(f"- {status} **{result.provider}**: {result.error or 'Success'}")

        summary_path.write_text("\n".join(summary_lines))
