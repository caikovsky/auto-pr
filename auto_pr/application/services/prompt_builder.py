"""Prompt builder service for AI generation."""

from auto_pr.domain.entities import GitContext, JiraTicket


class PromptBuilder:
    """Builds prompts for AI PR description generation."""

    def build(
        self,
        ticket: JiraTicket | None,
        context: GitContext,
        template: str | None = None,
    ) -> str:
        """Build a comprehensive prompt for AI.

        Args:
            ticket: Jira ticket info (optional).
            context: Git context with commits, diff, etc.
            template: PR template to fill (optional).

        Returns:
            Formatted prompt string.
        """
        sections = [self._build_instruction()]

        if ticket:
            sections.append(self._build_ticket_section(ticket))

        sections.append(self._build_git_section(context))

        if template:
            sections.append(self._build_template_section(template))

        sections.append(self._build_output_requirements())

        return "\n\n".join(sections)

    def _build_instruction(self) -> str:
        """Build the main instruction."""
        return """You are a senior software engineer writing a pull request description.
Analyze the provided information and generate a clear, professional PR description.

Focus on:
- What changes were made and why
- Technical approach taken
- Key files and areas impacted
- Any testing considerations"""

    def _build_ticket_section(self, ticket: JiraTicket) -> str:
        """Build the Jira ticket section."""
        lines = [
            "## JIRA TICKET",
            f"Key: {ticket.key}",
            f"Title: {ticket.title}",
            f"Type: {ticket.ticket_type}",
            f"URL: {ticket.url}",
        ]

        if ticket.description:
            lines.append(f"\nDescription:\n{ticket.description}")

        return "\n".join(lines)

    def _build_git_section(self, context: GitContext) -> str:
        """Build the git context section."""
        lines = [
            "## GIT CONTEXT",
            f"Branch: {context.branch}",
            f"Base: {context.base_branch}",
            f"Commits: {context.commit_count}",
            f"Files changed: {context.file_count}",
        ]

        if context.commits:
            lines.append("\nCommit messages:")
            for commit in context.commits[:20]:  # Limit commits
                lines.append(f"  - {commit}")

        if context.changed_files:
            lines.append("\nChanged files:")
            for file in context.changed_files[:30]:  # Limit files
                lines.append(f"  - {file}")

        if context.diff_stat:
            lines.append(f"\nDiff stats:\n{context.diff_stat}")

        if context.diff:
            lines.append(f"\nDiff (may be truncated):\n```\n{context.diff}\n```")

        return "\n".join(lines)

    def _build_template_section(self, template: str) -> str:
        """Build the template section."""
        return f"""## PR TEMPLATE TO FILL

Fill in the following template. Keep the structure and headings.
Replace comments/placeholders with actual content.

```markdown
{template}
```"""

    def _build_output_requirements(self) -> str:
        """Build output requirements."""
        return """## OUTPUT REQUIREMENTS

- Output ONLY the PR description in markdown format
- Do NOT include any preamble or explanation
- Do NOT wrap in code blocks
- Fill in ALL template sections if a template was provided
- Be concise but thorough
- Use professional language"""
