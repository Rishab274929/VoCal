"""Research module: web search + LLM-driven evidence gathering."""

from sigma_prophet.research.evidence import EvidenceBundle, ResearchAgent
from sigma_prophet.research.web_search import (
    BraveSearch,
    NullSearch,
    SearchBackend,
    SearchResult,
    TavilySearch,
    get_search_backend,
)

__all__ = [
    "BraveSearch",
    "TavilySearch",
    "NullSearch",
    "SearchBackend",
    "SearchResult",
    "EvidenceBundle",
    "ResearchAgent",
    "get_search_backend",
]
