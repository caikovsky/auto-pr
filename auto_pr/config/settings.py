"""Configuration settings."""

import tomllib
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict


class Settings(BaseModel):
    """Application settings."""

    model_config = ConfigDict(frozen=True)

    # AI provider preference: auto, gemini, copilot, or agent
    ai_provider: Literal["auto", "gemini", "copilot", "agent"] = "auto"

    # Default base branch
    base_branch: str = "main"

    # Jira base URL (for constructing ticket URLs)
    jira_base_url: str = "https://everlong.atlassian.net"


def get_config_path() -> Path:
    """Get the config file path."""
    return Path.home() / ".config" / "autopr" / "config.toml"


def load_settings() -> Settings:
    """Load settings from config file or return defaults.

    Returns:
        Settings instance with values from config or defaults.
    """
    config_path = get_config_path()

    if not config_path.exists():
        return Settings()

    try:
        with open(config_path, "rb") as f:
            data = tomllib.load(f)
        return Settings(**data)
    except Exception:
        # Return defaults on any error
        return Settings()


def save_default_config() -> Path:
    """Create a default config file if it doesn't exist.

    Returns:
        Path to the config file.
    """
    config_path = get_config_path()

    if config_path.exists():
        return config_path

    config_path.parent.mkdir(parents=True, exist_ok=True)

    default_config = """# auto-pr configuration
# AI provider: auto, gemini, copilot, or agent
ai_provider = "auto"

# Default base branch for PRs
base_branch = "main"

# Jira instance URL
jira_base_url = "https://everlong.atlassian.net"
"""

    config_path.write_text(default_config)
    return config_path
