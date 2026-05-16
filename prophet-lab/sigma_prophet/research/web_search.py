"""Web search backends.

Brave Search and Tavily are supported, plus a NullSearch fallback for
offline/no-API-key runs. All backends return a list of ``SearchResult``.
"""

from __future__ import annotations

import logging
import os
from abc import ABC, abstractmethod
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)


@dataclass
class SearchResult:
    title: str
    url: str
    snippet: str
    source: str = ""

    def to_evidence_line(self) -> str:
        url = f" ({self.url})" if self.url else ""
        return f"- {self.title}{url}: {self.snippet}".strip()


class SearchBackend(ABC):
    """Abstract base for web search providers."""

    name: str = "base"

    @abstractmethod
    def search(self, query: str, *, limit: int = 5, timeout: int = 25) -> list[SearchResult]:
        ...


class BraveSearch(SearchBackend):
    """Brave Search API."""

    name = "brave"
    ENDPOINT = "https://api.search.brave.com/res/v1/web/search"

    def __init__(self, api_key: str | None = None):
        self.api_key = api_key or os.environ.get("BRAVE_API_KEY", "")

    def search(self, query: str, *, limit: int = 5, timeout: int = 25) -> list[SearchResult]:
        if not self.api_key:
            logger.warning("BRAVE_API_KEY not set; skipping Brave search")
            return []
        headers = {
            "Accept": "application/json",
            "X-Subscription-Token": self.api_key,
        }
        params = {"q": query, "count": limit}
        try:
            resp = httpx.get(self.ENDPOINT, params=params, headers=headers, timeout=timeout)
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.warning("Brave search failed for %r: %s", query, exc)
            return []
        data = resp.json()
        results = []
        for item in (data.get("web", {}) or {}).get("results", [])[:limit]:
            results.append(
                SearchResult(
                    title=item.get("title", "")[:200],
                    url=item.get("url", ""),
                    snippet=item.get("description", "")[:400],
                    source=self.name,
                )
            )
        return results


class TavilySearch(SearchBackend):
    """Tavily search API (https://tavily.com)."""

    name = "tavily"
    ENDPOINT = "https://api.tavily.com/search"

    def __init__(self, api_key: str | None = None):
        self.api_key = api_key or os.environ.get("TAVILY_API_KEY", "")

    def search(self, query: str, *, limit: int = 5, timeout: int = 25) -> list[SearchResult]:
        if not self.api_key:
            logger.warning("TAVILY_API_KEY not set; skipping Tavily search")
            return []
        payload = {
            "api_key": self.api_key,
            "query": query,
            "max_results": limit,
            "search_depth": "basic",
            "include_answer": False,
        }
        try:
            resp = httpx.post(self.ENDPOINT, json=payload, timeout=timeout)
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.warning("Tavily search failed for %r: %s", query, exc)
            return []
        data = resp.json()
        results = []
        for item in (data.get("results") or [])[:limit]:
            results.append(
                SearchResult(
                    title=item.get("title", "")[:200],
                    url=item.get("url", ""),
                    snippet=(item.get("content") or item.get("snippet", ""))[:400],
                    source=self.name,
                )
            )
        return results


class NullSearch(SearchBackend):
    """No-op backend. Use when no search API key is available."""

    name = "none"

    def search(self, query: str, *, limit: int = 5, timeout: int = 25) -> list[SearchResult]:
        return []


def get_search_backend(name: str | None = None) -> SearchBackend:
    """Construct the configured backend, falling back to NullSearch."""
    target = (name or "").strip().lower()
    if target in ("brave", ""):
        backend: SearchBackend = BraveSearch()
        if backend.api_key:
            return backend
    if target in ("tavily", "") and os.environ.get("TAVILY_API_KEY"):
        return TavilySearch()
    if target == "brave":
        return BraveSearch()
    if target == "tavily":
        return TavilySearch()
    if target == "none":
        return NullSearch()
    return NullSearch()
