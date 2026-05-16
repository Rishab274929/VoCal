"""Multi-model ensemble forecaster.

Aggregates LLMForecaster heads with configurable weights and applies
the calibration pipeline. Heads can be on different providers (Wafer,
OpenRouter, OpenAI) — each ModelSpec carries its own provider.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from sigma_prophet.config import CalibrationConfig, ModelSpec
from sigma_prophet.prediction.calibration import apply_calibration
from sigma_prophet.prediction.forecaster import ForecastResult, LLMForecaster

logger = logging.getLogger(__name__)


@dataclass
class EnsembleResult:
    """Combined probabilities across all model heads."""

    probabilities: dict[str, float]
    rationale: str
    per_model: list[ForecastResult] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def as_ordered(self, outcomes: list[str]) -> list[float]:
        return [self.probabilities.get(o, 0.0) for o in outcomes]


class EnsembleForecaster:
    """Weighted ensemble of LLM heads with calibration.

    ``api_key`` is a legacy convenience for single-provider setups; with
    mixed providers each head resolves its own key via env vars
    (WAFER_API_KEY / OPENROUTER_API_KEY / OPENAI_API_KEY).
    """

    def __init__(
        self,
        models: list[ModelSpec],
        calibration: CalibrationConfig,
        *,
        api_key: str | None = None,
        client: Any | None = None,
    ):
        if not models:
            raise ValueError("EnsembleForecaster requires at least one model")
        self.heads = [LLMForecaster(spec, api_key=api_key, client=client) for spec in models]
        self.weights = [max(0.0, m.weight) for m in models]
        total_w = sum(self.weights) or 1.0
        self.weights = [w / total_w for w in self.weights]
        self.calibration = calibration

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
        evidence: str | None = None,
        market_prior: list[float] | None = None,
    ) -> EnsembleResult:
        """Run all heads and combine. If ``evidence`` is provided, heads use the reconcile prompt."""

        results: list[ForecastResult] = []
        for head in self.heads:
            if evidence:
                res = head.reconcile_with_evidence(
                    title,
                    outcomes,
                    evidence=evidence,
                    rules=rules,
                    close_time=close_time,
                )
            else:
                res = head.forecast(
                    title,
                    outcomes,
                    rules=rules,
                    description=description,
                    category=category,
                    close_time=close_time,
                    subtitle=subtitle,
                )
            results.append(res)

        # combine in log-odds-friendly arithmetic mean (already proper probability simplex)
        combined: dict[str, float] = {o: 0.0 for o in outcomes}
        for w, res in zip(self.weights, results, strict=True):
            for o in outcomes:
                combined[o] += w * res.probabilities.get(o, 0.0)

        ordered = [combined[o] for o in outcomes]
        calibrated = apply_calibration(
            ordered,
            prior=market_prior,
            shrink_to_prior_weight=self.calibration.shrink_to_prior,
            min_prob=self.calibration.min_prob,
            max_prob=self.calibration.max_prob,
            log_odds_smoothing=self.calibration.log_odds_smoothing,
        )
        final = dict(zip(outcomes, calibrated, strict=True))

        rationale_parts = []
        for res in results:
            if res.rationale:
                rationale_parts.append(f"[{res.model}] {res.rationale.strip()}")
        rationale = "\n".join(rationale_parts)[:4000]

        return EnsembleResult(
            probabilities=final,
            rationale=rationale,
            per_model=results,
            metadata={
                "weights": self.weights,
                "n_models": len(self.heads),
                "calibration": {
                    "shrink_to_prior": self.calibration.shrink_to_prior,
                    "min_prob": self.calibration.min_prob,
                    "max_prob": self.calibration.max_prob,
                    "log_odds_smoothing": self.calibration.log_odds_smoothing,
                    "used_market_prior": market_prior is not None,
                },
            },
        )
