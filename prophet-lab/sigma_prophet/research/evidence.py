"""Evidence aggregation: decompose → search → bundle snippets."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from sigma_prophet.config import ResearchConfig
from sigma_prophet.prediction.forecaster import LLMForecaster
from sigma_prophet.prediction.prompts import DECOMPOSE_SYSTEM, build_decompose_user_prompt
from sigma_prophet.research.web_search import SearchBackend, SearchResult
from sigma_prophet.utils.json_utils import extract_json_object

logger = logging.getLogger(__name__)


@dataclass
class EvidenceBundle:
    """Collected snippets ready to feed into the reconciliation prompt."""

    queries: list[str]
    results: list[SearchResult] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_prompt_text(self, *, max_chars: int = 6000) -> str:
        if not self.results:
            return ""
        lines: list[str] = []
        for r in self.results:
            line = r.to_evidence_line()
            if not line:
                continue
            lines.append(line)
        joined = "\n".join(lines)
        return joined[:max_chars]


class ResearchAgent:
    """Decompose a question into queries, run search, return the evidence bundle."""

    def __init__(
        self,
        decomposer: LLMForecaster,
        search_backend: SearchBackend,
        cfg: ResearchConfig,
    ):
        self.decomposer = decomposer
        self.search_backend = search_backend
        self.cfg = cfg

    def _decompose(self, title: str, outcomes: list[str]) -> list[str]:
        if not self.cfg.enabled:
            return []
        try:
            raw = self.decomposer._call(
                DECOMPOSE_SYSTEM,
                build_decompose_user_prompt(title, outcomes),
            )
            parsed = extract_json_object(raw)
            queries = parsed.get("queries") or []
        except Exception as exc:
            logger.warning("Decompose failed; using fallback query: %s", exc)
            return [title[:160]]
        clean = [str(q).strip() for q in queries if isinstance(q, str) and q.strip()]
        if not clean:
            return [title[:160]]
        return clean[: self.cfg.max_queries]

    def gather(self, title: str, outcomes: list[str]) -> EvidenceBundle:
        if not self.cfg.enabled:
            return EvidenceBundle(queries=[], results=[], metadata={"disabled": True})

        queries = self._decompose(title, outcomes)
        all_results: list[SearchResult] = []
        for q in queries:
            res = self.search_backend.search(
                q,
                limit=self.cfg.max_results_per_query,
                timeout=self.cfg.timeout_sec,
            )
            logger.info("search %r -> %d hits (%s)", q[:80], len(res), self.search_backend.name)
            all_results.extend(res)

        # de-duplicate by URL while preserving order
        seen: set[str] = set()
        unique: list[SearchResult] = []
        for r in all_results:
            key = r.url or r.title
            if key in seen:
                continue
            seen.add(key)
            unique.append(r)

        return EvidenceBundle(
            queries=queries,
            results=unique,
            metadata={
                "backend": self.search_backend.name,
                "n_queries": len(queries),
                "n_results": len(unique),
            },
        )
