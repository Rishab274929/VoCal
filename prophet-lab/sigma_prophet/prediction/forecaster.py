"""LLM-based forecaster.

Single-model probability estimator. Used standalone or as one head of the
EnsembleForecaster.

Backed by ``LLMClient`` which speaks OpenAI-compatible /v1/chat/completions
against any of: wafer, openrouter, openai, custom.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from sigma_prophet.config import ModelSpec
from sigma_prophet.prediction.llm_client import LLMClient, LLMError
from sigma_prophet.prediction.prompts import (
    FORECAST_SYSTEM,
    RECONCILE_SYSTEM,
    build_forecast_user_prompt,
    build_reconcile_user_prompt,
)
from sigma_prophet.utils.json_utils import extract_json_object
from sigma_prophet.utils.retry import with_retries

logger = logging.getLogger(__name__)


@dataclass
class ForecastResult:
    """One probability distribution + rationale + raw model output."""

    probabilities: dict[str, float]
    rationale: str
    model: str
    raw: str = ""
    cost_estimate_usd: float = 0.0
    metadata: dict[str, Any] = field(default_factory=dict)

    def as_ordered(self, outcomes: list[str]) -> list[float]:
        """Return probs ordered to match ``outcomes`` (missing keys → 0)."""
        return [float(self.probabilities.get(o, 0.0)) for o in outcomes]


def _coerce_probabilities(data: dict[str, Any], outcomes: list[str]) -> dict[str, float]:
    """Accept several JSON shapes and snap onto the supplied outcome labels."""
    raw = data.get("probabilities", data.get("probs"))
    pairs: list[tuple[str, float]] = []
    if isinstance(raw, dict):
        pairs = [(str(k), float(v)) for k, v in raw.items()]
    elif isinstance(raw, list):
        for item in raw:
            if not isinstance(item, dict):
                continue
            market = item.get("market") or item.get("outcome") or item.get("label")
            prob = item.get("probability") or item.get("prob") or item.get("p")
            if market is None or prob is None:
                continue
            pairs.append((str(market), float(prob)))
    else:
        raise ValueError(f"Unrecognized probabilities shape: {type(raw)!r}")

    if pairs and any(p > 1.5 for _m, p in pairs):
        pairs = [(m, p / 100.0) for m, p in pairs]

    lookup = {o.lower().strip(): o for o in outcomes}
    out: dict[str, float] = {o: 0.0 for o in outcomes}
    for market, prob in pairs:
        key = market.lower().strip()
        if key in lookup:
            out[lookup[key]] += max(0.0, float(prob))
            continue
        for canonical_lower, canonical in lookup.items():
            if key in canonical_lower or canonical_lower in key:
                out[canonical] += max(0.0, float(prob))
                break
    return out


class LLMForecaster:
    """Single-model LLM forecaster.

    ``client`` lets tests inject a stub. If absent, an LLMClient is built
    from the spec's ``provider`` and resolved API key.
    """

    def __init__(
        self,
        spec: ModelSpec,
        api_key: str | None = None,
        client: LLMClient | Any | None = None,
    ):
        self.spec = spec
        self._explicit_client = client
        self._api_key = api_key
        self._client_cache: LLMClient | None = None

    def _client(self) -> Any:
        if self._explicit_client is not None:
            return self._explicit_client
        if self._client_cache is not None:
            return self._client_cache
        self._client_cache = LLMClient(
            provider=self.spec.provider,
            api_key=self._api_key,
            base_url=self.spec.base_url,
        )
        return self._client_cache

    def _call(self, system: str, user: str) -> str:
        def _do() -> str:
            client = self._client()
            response = client.chat(
                model=self.spec.name,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                max_tokens=self.spec.max_tokens,
                temperature=self.spec.temperature,
            )
            return (response.content or "").strip()

        label = f"{self.spec.provider}:{self.spec.name}"
        return with_retries(_do, max_attempts=3, initial_delay=2.0, label=label)

    def forecast(
        self,
        title: str,
        outcomes: list[str],
        *,
        rules: str | None = None,
        description: str | None = None,
        category: str | None = None,
        close_time: str | None = None,
        subtitle: str | None = None,
    ) -> ForecastResult:
        """Run a one-shot forecast without external research."""
        user = build_forecast_user_prompt(
            title,
            outcomes,
            rules=rules,
            description=description,
            category=category,
            close_time=close_time,
            subtitle=subtitle,
        )
        try:
            raw = self._call(FORECAST_SYSTEM, user)
            parsed = extract_json_object(raw)
        except (LLMError, ValueError, Exception) as exc:
            logger.warning("Forecast failed (%s): %s", self.spec.name, exc)
            uniform = 1.0 / max(1, len(outcomes))
            return ForecastResult(
                probabilities={o: uniform for o in outcomes},
                rationale=f"Fallback (uniform) due to error: {exc}",
                model=self.spec.name,
                raw="",
                metadata={"error": str(exc), "provider": self.spec.provider},
            )
        probs = _coerce_probabilities(parsed, outcomes)
        rationale = str(parsed.get("rationale", "")).strip()
        return ForecastResult(
            probabilities=probs,
            rationale=rationale,
            model=self.spec.name,
            raw=raw,
            metadata={"provider": self.spec.provider},
        )

    def reconcile_with_evidence(
        self,
        title: str,
        outcomes: list[str],
        evidence: str,
        *,
        rules: str | None = None,
        close_time: str | None = None,
    ) -> ForecastResult:
        """Forecast conditioned on a bundle of web-search snippets."""
        user = build_reconcile_user_prompt(
            title,
            outcomes,
            evidence,
            rules=rules,
            close_time=close_time,
        )
        try:
            raw = self._call(RECONCILE_SYSTEM, user)
            parsed = extract_json_object(raw)
        except (LLMError, ValueError, Exception) as exc:
            logger.warning("Reconcile failed (%s): %s", self.spec.name, exc)
            return self.forecast(
                title,
                outcomes,
                rules=rules,
                close_time=close_time,
            )
        probs = _coerce_probabilities(parsed, outcomes)
        rationale = str(parsed.get("rationale", "")).strip()
        return ForecastResult(
            probabilities=probs,
            rationale=rationale,
            model=self.spec.name,
            raw=raw,
            metadata={
                "evidence_chars": len(evidence),
                "provider": self.spec.provider,
            },
        )


# Backwards-compatibility alias.
# Previous releases exported ``ClaudeForecaster``; keep the name resolvable
# while the rest of the codebase migrates.
ClaudeForecaster = LLMForecaster
