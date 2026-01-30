"""Jira ticket entity."""

import re
from typing import Self

from pydantic import BaseModel, ConfigDict, Field, field_validator


class JiraTicket(BaseModel):
    """Immutable Jira ticket entity."""

    model_config = ConfigDict(frozen=True)

    key: str = Field(description="Ticket key (e.g., TLAB-123)")
    title: str = Field(description="Ticket title/summary")
    description: str = Field(default="", description="Ticket description")
    ticket_type: str = Field(description="Issue type (Task, Story, Bug, etc.)")
    url: str = Field(description="Full URL to the ticket")

    @field_validator("key")
    @classmethod
    def validate_key_format(cls, v: str) -> str:
        """Validate Jira key format: PROJECT-123."""
        if not re.match(r"^[A-Z]+-\d+$", v):
            raise ValueError(f"Invalid Jira key format: {v}")
        return v

    @classmethod
    def from_acli_response(cls, data: dict[str, object]) -> Self:
        """Create from acli JSON response."""
        key = str(data.get("key", ""))
        fields = data.get("fields", {})
        if not isinstance(fields, dict):
            fields = {}

        # Extract description text from Atlassian Document Format
        description = ""
        desc_field = fields.get("description")
        if isinstance(desc_field, dict):
            content = desc_field.get("content", [])
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "paragraph":
                        for item in block.get("content", []):
                            if isinstance(item, dict) and item.get("type") == "text":
                                description += str(item.get("text", ""))
        elif isinstance(desc_field, str):
            description = desc_field

        issue_type = fields.get("issuetype", {})
        type_name = issue_type.get("name", "Task") if isinstance(issue_type, dict) else "Task"

        return cls(
            key=key,
            title=str(fields.get("summary", "")),
            description=description,
            ticket_type=str(type_name),
            url=f"https://everlong.atlassian.net/browse/{key}",
        )
