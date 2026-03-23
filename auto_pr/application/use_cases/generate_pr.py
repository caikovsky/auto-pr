"""Generate PR description use case."""

from dataclasses import dataclass

from auto_pr.domain.entities import GitContext, JiraTicket, PRDescription
from auto_pr.domain.interfaces import AIProvider, GitClient, JiraClient, PRClient
from auto_pr.application.services.prompt_builder import PromptBuilder


@dataclass
class GeneratePRResult:
    """Result of PR description generation."""

    title: str
    description: PRDescription
    ticket: JiraTicket | None
    context: GitContext
    ticket_error: str | None = None  # Warning if ticket fetch failed


class GeneratePRDescription:
    """Use case: Generate a PR description using AI."""

    def __init__(
        self,
        git_client: GitClient,
        jira_client: JiraClient,
        pr_client: PRClient,
        ai_provider: AIProvider,
        prompt_builder: PromptBuilder,
    ) -> None:
        self._git = git_client
        self._jira = jira_client
        self._pr = pr_client
        self._ai = ai_provider
        self._prompt = prompt_builder

    def execute(self, base_branch: str = "main") -> GeneratePRResult:
        """Execute the use case.

        Args:
            base_branch: Target branch for the PR.

        Returns:
            GeneratePRResult with title, description, ticket, and context.

        Raises:
            JiraTicketNotFoundError: If ticket key found but doesn't exist.
            AIGenerationError: If AI fails to generate.
        """
        # Get git context
        context = self._git.get_context(base_branch)

        # Extract and fetch Jira ticket (optional)
        ticket: JiraTicket | None = None
        ticket_error: str | None = None
        ticket_key = self._git.extract_ticket_key(context.branch)
        if ticket_key:
            try:
                ticket = self._jira.fetch(ticket_key)
            except Exception as e:
                # Continue without ticket, but record the error for warning
                ticket_error = f"Could not fetch {ticket_key}: {e}"

        # Get PR template
        template = self._pr.get_pr_template()

        # Build prompt and generate description
        prompt = self._prompt.build(ticket, context, template)
        description = self._ai.generate(prompt)

        # Build title
        if ticket:
            title = f"[{ticket.key}] - {ticket.clean_title}"
        else:
            # Use branch name as title
            branch_title = context.branch.replace("/", ": ").replace("-", " ").title()
            title = branch_title

        return GeneratePRResult(
            title=title,
            description=description,
            ticket=ticket,
            context=context,
            ticket_error=ticket_error,
        )
