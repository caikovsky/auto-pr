"""Shared test fixtures."""

import pytest

from auto_pr.domain.entities import GitContext, JiraTicket, PRDescription


@pytest.fixture
def sample_ticket() -> JiraTicket:
    """Sample Jira ticket for testing."""
    return JiraTicket(
        key="TLAB-123",
        title="Implement feature X",
        description="As a user, I want to do something",
        ticket_type="Story",
        url="https://everlong.atlassian.net/browse/TLAB-123",
    )


@pytest.fixture
def sample_context() -> GitContext:
    """Sample git context for testing."""
    return GitContext(
        branch="task/TLAB-123-feature-x",
        base_branch="main",
        commits=["feat: add feature X", "test: add tests"],
        changed_files=["src/feature.py", "tests/test_feature.py"],
        diff="+ new code here",
        diff_stat="2 files changed, 50 insertions(+)",
    )


@pytest.fixture
def sample_description() -> PRDescription:
    """Sample PR description for testing."""
    return PRDescription(
        content="## Summary\n\nThis PR implements feature X.",
        ai_provider="gemini",
    )
