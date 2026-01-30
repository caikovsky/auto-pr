"""Domain entities - immutable data structures."""

from auto_pr.domain.entities.existing_pr import ExistingPR
from auto_pr.domain.entities.git_context import GitContext
from auto_pr.domain.entities.jira_ticket import JiraTicket
from auto_pr.domain.entities.pr_description import PRDescription

__all__ = ["ExistingPR", "GitContext", "JiraTicket", "PRDescription"]
