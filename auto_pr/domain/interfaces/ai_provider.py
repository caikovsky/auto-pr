"""AI provider interface."""

from abc import ABC, abstractmethod

from auto_pr.domain.entities import PRDescription


class AIProvider(ABC):
    """Interface for AI providers."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Provider name for display."""
        ...

    @abstractmethod
    def is_available(self) -> bool:
        """Check if this provider is available (CLI installed)."""
        ...

    @abstractmethod
    def generate(self, prompt: str) -> PRDescription:
        """Generate PR description from prompt."""
        ...
