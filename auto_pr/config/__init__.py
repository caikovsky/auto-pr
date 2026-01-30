"""Configuration module."""

from auto_pr.config.settings import (
    Settings,
    get_config_path,
    load_settings,
)

__all__ = [
    "Settings",
    "get_config_path",
    "load_settings",
]
