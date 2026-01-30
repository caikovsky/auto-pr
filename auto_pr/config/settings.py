"""Configuration settings."""

import tomllib
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict


# Default config content - single source of truth
DEFAULT_CONFIG = '''# autopr configuration

# AI provider: auto, gemini, copilot, or agent
ai_provider = "auto"

# Default base branch for PRs
base_branch = "main"

# Jira base URL
jira_base_url = "https://everlong.atlassian.net"

# Prompt instructions - what the AI should focus on
# Customize this to change the AI's behavior
prompt_instructions = """
- What changes were made and why
- Technical approach taken
- Key files and areas impacted
- Any testing considerations
"""

# Output rules - formatting requirements for the AI
# Customize to enforce your preferred style
output_rules = """
- Output ONLY the PR description in markdown format
- Do NOT include any preamble or explanation
- Do NOT wrap in code blocks
- Fill in ALL template sections if a template was provided
- Be concise but thorough
- Use professional language
"""
'''


class Settings(BaseModel):
    """Application settings."""

    model_config = ConfigDict(frozen=True)

    # AI provider preference: auto, gemini, copilot, or agent
    ai_provider: Literal["auto", "gemini", "copilot", "agent"] = "auto"

    # Default base branch
    base_branch: str = "main"

    # Jira base URL (for constructing ticket URLs)
    jira_base_url: str = "https://everlong.atlassian.net"

    # Prompt customization (required - loaded from config)
    prompt_instructions: str
    output_rules: str


def get_config_path() -> Path:
    """Get the config file path."""
    return Path.home() / ".config" / "autopr" / "config.toml"


def _ensure_config_exists() -> Path:
    """Ensure config file exists, create with defaults if not.

    Returns:
        Path to the config file.
    """
    config_path = get_config_path()

    if not config_path.exists():
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(DEFAULT_CONFIG)

    return config_path


def load_settings() -> Settings:
    """Load settings from config file.

    Creates default config if it doesn't exist.

    Returns:
        Settings instance with values from config.
    """
    config_path = _ensure_config_exists()

    with open(config_path, "rb") as f:
        data = tomllib.load(f)

    return Settings(**data)
