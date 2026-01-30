"""Git context entity."""

from pydantic import BaseModel, ConfigDict, Field, field_validator


class GitContext(BaseModel):
    """Immutable git context for PR generation."""

    model_config = ConfigDict(frozen=True)

    branch: str = Field(description="Current branch name")
    base_branch: str = Field(default="main", description="Target branch for PR")
    commits: list[str] = Field(default_factory=list, description="Commit messages")
    changed_files: list[str] = Field(default_factory=list, description="List of changed files")
    diff: str = Field(default="", description="Git diff content")
    diff_stat: str = Field(default="", description="Git diff --stat output")

    @field_validator("branch")
    @classmethod
    def branch_not_empty(cls, v: str) -> str:
        """Validate branch is not empty."""
        if not v.strip():
            raise ValueError("Branch cannot be empty")
        return v

    @property
    def commit_count(self) -> int:
        """Number of commits."""
        return len(self.commits)

    @property
    def file_count(self) -> int:
        """Number of changed files."""
        return len(self.changed_files)
