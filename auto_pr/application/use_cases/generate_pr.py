"""Generate PR description use case."""

from dataclasses import dataclass

from auto_pr.domain.entities import GitContext, JiraTicket, PRDescription
from auto_pr.domain.exceptions import BranchParseError
from auto_pr.domain.interfaces import AIProvider, GitClient, JiraClient, PRClient
from auto_pr.application.services.prompt_builder import PromptBuilder


@dataclass
class GeneratePRResult:
    """Result of PR description generation."""

    title: str
    description: PRDescription
    ticket: JiraTicket | None
    context: GitContext


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
            BranchParseError: If ticket cannot be extracted from branch.
            JiraTicketNotFoundError: If ticket doesn't exist.
            AIGenerationError: If AI fails to generate.
        """
        # Get git context
        context = self._git.get_context(base_branch)

        # Extract and fetch Jira ticket
        ticket_key = self._git.extract_ticket_key(context.branch)
        if not ticket_key:
            raise BranchParseError(context.branch)

        ticket = self._jira.fetch(ticket_key)

        # Get PR template
        template = self._pr.get_pr_template()

        # Build prompt and generate description
        prompt = self._prompt.build(ticket, context, template)
        description = self._ai.generate(prompt)

        # Build title
        title = f"[{ticket.key}] {ticket.title}"

        return GeneratePRResult(
            title=title,
            description=description,
            ticket=ticket,
            context=context,
        )
