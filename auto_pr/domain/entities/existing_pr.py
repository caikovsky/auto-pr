"""Existing PR entity."""

from pydantic import BaseModel, ConfigDict


class ExistingPR(BaseModel):
    """Immutable existing PR info."""

    model_config = ConfigDict(frozen=True)

    number: int
    title: str
    body: str
    url: str
    draft: bool = False
