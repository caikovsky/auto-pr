"""Domain interfaces - contracts for infrastructure."""

from auto_pr.domain.interfaces.ai_provider import AIProvider
from auto_pr.domain.interfaces.git_client import GitClient
from auto_pr.domain.interfaces.jira_client import JiraClient
from auto_pr.domain.interfaces.pr_client import PRClient

__all__ = ["AIProvider", "GitClient", "JiraClient", "PRClient"]
