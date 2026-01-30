"""Application use cases."""

from auto_pr.application.use_cases.compare_ai import (
    AIComparisonResult,
    CompareAIOutputs,
    CompareAIResult,
)
from auto_pr.application.use_cases.create_pr import CreatePRResult, CreatePullRequest
from auto_pr.application.use_cases.generate_pr import (
    GeneratePRDescription,
    GeneratePRResult,
)

__all__ = [
    "AIComparisonResult",
    "CompareAIOutputs",
    "CompareAIResult",
    "CreatePRResult",
    "CreatePullRequest",
    "GeneratePRDescription",
    "GeneratePRResult",
]
