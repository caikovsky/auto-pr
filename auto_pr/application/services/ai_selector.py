"""AI provider selector service."""

from auto_pr.domain.exceptions import AIProviderNotFoundError
from auto_pr.domain.interfaces import AIProvider
from auto_pr.infrastructure.ai import AgentProvider, CopilotProvider, GeminiProvider


class AISelector:
    """Selects and provides AI providers."""

    # Priority order for auto-detection
    PROVIDERS: list[type[AIProvider]] = [
        GeminiProvider,
        CopilotProvider,
        AgentProvider,
    ]

    PROVIDER_MAP: dict[str, type[AIProvider]] = {
        "gemini": GeminiProvider,
        "copilot": CopilotProvider,
        "agent": AgentProvider,
    }

    def get_provider(self, name: str | None = None) -> AIProvider:
        """Get an AI provider by name or auto-detect.

        Args:
            name: Provider name ("gemini", "copilot", "agent") or None for auto.

        Returns:
            An available AIProvider instance.

        Raises:
            AIProviderNotFoundError: If requested provider not found or none available.
        """
        if name:
            return self._get_specific_provider(name)
        return self._auto_detect_provider()

    def get_all_available(self) -> list[AIProvider]:
        """Get all available AI providers.

        Returns:
            List of available AIProvider instances.
        """
        available = []
        for provider_class in self.PROVIDERS:
            provider = provider_class()
            if provider.is_available():
                available.append(provider)
        return available

    def _get_specific_provider(self, name: str) -> AIProvider:
        """Get a specific provider by name."""
        provider_class = self.PROVIDER_MAP.get(name.lower())

        if not provider_class:
            raise AIProviderNotFoundError(name)

        provider = provider_class()

        if not provider.is_available():
            raise AIProviderNotFoundError(name)

        return provider

    def _auto_detect_provider(self) -> AIProvider:
        """Auto-detect the first available provider."""
        for provider_class in self.PROVIDERS:
            provider = provider_class()
            if provider.is_available():
                return provider

        raise AIProviderNotFoundError()
