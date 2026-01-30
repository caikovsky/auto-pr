"""Tests for domain entities."""

import pytest
from pydantic import ValidationError

from auto_pr.domain.entities import GitContext, JiraTicket, PRDescription


class TestJiraTicket:
    """Tests for JiraTicket entity."""

    def test_create_valid_ticket(self) -> None:
        """Test creating a valid ticket."""
        ticket = JiraTicket(
            key="TLAB-123",
            title="Fix bug",
            description="Description here",
            ticket_type="Task",
            url="https://example.atlassian.net/browse/TLAB-123",
        )

        assert ticket.key == "TLAB-123"
        assert ticket.title == "Fix bug"
        assert ticket.description == "Description here"
        assert ticket.ticket_type == "Task"

    def test_invalid_key_format_raises(self) -> None:
        """Test that invalid key format raises ValidationError."""
        with pytest.raises(ValidationError):
            JiraTicket(
                key="invalid",
                title="Fix bug",
                description="",
                ticket_type="Task",
                url="https://example.com",
            )

    def test_ticket_is_immutable(self) -> None:
        """Test that ticket cannot be modified after creation."""
        ticket = JiraTicket(
            key="TLAB-123",
            title="Fix bug",
            description="",
            ticket_type="Task",
            url="https://example.com",
        )

        with pytest.raises(ValidationError):
            ticket.title = "New title"  # type: ignore[misc]

    def test_from_acli_response(self) -> None:
        """Test creating ticket from acli JSON response."""
        acli_data = {
            "key": "TLAB-123",
            "fields": {
                "summary": "Fix the bug",
                "description": {
                    "content": [
                        {
                            "type": "paragraph",
                            "content": [{"type": "text", "text": "Do something"}],
                        }
                    ]
                },
                "issuetype": {"name": "Story"},
            },
        }

        ticket = JiraTicket.from_acli_response(acli_data)

        assert ticket.key == "TLAB-123"
        assert ticket.title == "Fix the bug"
        assert ticket.description == "Do something"
        assert ticket.ticket_type == "Story"

    def test_from_acli_response_empty_description(self) -> None:
        """Test handling empty description in acli response."""
        acli_data = {
            "key": "TLAB-456",
            "fields": {
                "summary": "Task title",
                "description": None,
                "issuetype": {"name": "Task"},
            },
        }

        ticket = JiraTicket.from_acli_response(acli_data)

        assert ticket.key == "TLAB-456"
        assert ticket.description == ""


class TestGitContext:
    """Tests for GitContext entity."""

    def test_create_valid_context(self) -> None:
        """Test creating valid git context."""
        context = GitContext(
            branch="task/TLAB-123",
            base_branch="main",
            commits=["feat: add feature", "fix: bug fix"],
            changed_files=["src/main.py", "tests/test_main.py"],
            diff="+ new code",
            diff_stat="2 files changed",
        )

        assert context.branch == "task/TLAB-123"
        assert context.commit_count == 2
        assert context.file_count == 2

    def test_empty_branch_raises(self) -> None:
        """Test that empty branch raises ValidationError."""
        with pytest.raises(ValidationError):
            GitContext(branch="", base_branch="main")

    def test_whitespace_branch_raises(self) -> None:
        """Test that whitespace-only branch raises ValidationError."""
        with pytest.raises(ValidationError):
            GitContext(branch="   ", base_branch="main")

    def test_context_is_immutable(self) -> None:
        """Test that context cannot be modified after creation."""
        context = GitContext(branch="main", base_branch="develop")

        with pytest.raises(ValidationError):
            context.branch = "other"  # type: ignore[misc]


class TestPRDescription:
    """Tests for PRDescription entity."""

    def test_create_description(self) -> None:
        """Test creating PR description."""
        desc = PRDescription(content="## Summary\nThis PR adds...", ai_provider="gemini")

        assert "Summary" in desc.content
        assert desc.ai_provider == "gemini"
        assert not desc.is_empty

    def test_empty_description(self) -> None:
        """Test is_empty property."""
        desc = PRDescription(content="", ai_provider="test")
        assert desc.is_empty

        desc2 = PRDescription(content="   ", ai_provider="test")
        assert desc2.is_empty

    def test_description_is_immutable(self) -> None:
        """Test that description cannot be modified."""
        desc = PRDescription(content="Test", ai_provider="test")

        with pytest.raises(ValidationError):
            desc.content = "Modified"  # type: ignore[misc]
