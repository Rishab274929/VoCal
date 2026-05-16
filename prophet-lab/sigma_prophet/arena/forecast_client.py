"""Forecast-track adapter.

Two integration modes:

1. **Local mode** — ``prophet forecast predict --local sigma_prophet.arena.forecast_client``
   invokes ``predict(event)`` once per event.
2. **Batch mode** — read ``events.json``, predict each, write ``predictions.json``.

The output shape matches Prophet Arena's expected schema:
``{"probabilities": [{"market": "...", "probability": 0.XX}], "rationale": "..."}``.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from sigma_prophet.config import Config, load_config
from sigma_prophet.prediction.ensemble import EnsembleForecaster
from sigma_prophet.research.evidence import ResearchAgent
from sigma_prophet.research.web_search import get_search_backend

logger = logging.getLogger(__name__)


def _normalize_event(event: dict[str, Any]) -> dict[str, Any]:
    """Accept several event shapes (Prophet Arena CLI vs sample datasets)."""
    out = dict(event)
    if "title" not in out:
        out["title"] = out.get("question") or out.get("market_ticker") or "Untitled question"
    out["outcomes"] = out.get("outcomes") or ["Yes", "No"]
    out["category"] = out.get("category") or "general"
    if "close_time" in out and out["close_time"] is not None:
        out["close_time"] = str(out["close_time"])
    return out


def _build_forecaster(cfg: Config) -> EnsembleForecaster:
    # Per-head API key resolution happens inside LLMClient based on provider.
    return EnsembleForecaster(models=cfg.models, calibration=cfg.calibration)


def _build_research(cfg: Config) -> ResearchAgent | None:
    if not cfg.research.enabled or not cfg.models:
        return None
    decomposer_spec = cfg.models[0]
    from sigma_prophet.prediction.forecaster import LLMForecaster

    decomposer = LLMForecaster(decomposer_spec)
    backend = get_search_backend(cfg.research.backend)
    return ResearchAgent(decomposer=decomposer, search_backend=backend, cfg=cfg.research)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def predict_event(
    event: dict[str, Any],
    cfg: Config | None = None,
) -> dict[str, Any]:
    """Run a single event through the ensemble and return the standard response."""
    cfg = cfg or load_config()
    forecaster = _build_forecaster(cfg)
    research = _build_research(cfg)
    return _predict_with_components(event, forecaster, research)


def _predict_with_components(
    event: dict[str, Any],
    forecaster: EnsembleForecaster,
    research: ResearchAgent | None,
) -> dict[str, Any]:
    norm = _normalize_event(event)
    title = norm["title"]
    outcomes = list(norm["outcomes"])
    evidence_text: str | None = None
    if research is not None:
        try:
            bundle = research.gather(title, outcomes)
            evidence_text = bundle.to_prompt_text() or None
        except Exception as exc:
            logger.warning("research failed for %s: %s", title[:60], exc)

    ens = forecaster.forecast(
        title=title,
        outcomes=outcomes,
        rules=norm.get("rules") or norm.get("description"),
        description=norm.get("description"),
        category=norm.get("category"),
        close_time=norm.get("close_time"),
        subtitle=norm.get("subtitle"),
        evidence=evidence_text,
    )
    return {
        "probabilities": [
            {"market": o, "probability": float(ens.probabilities.get(o, 0.0))}
            for o in outcomes
        ],
        "rationale": ens.rationale,
    }


def predict(event: dict[str, Any]) -> dict[str, Any]:
    """Entry point for ``prophet forecast predict --local sigma_prophet.arena.forecast_client``."""
    return predict_event(event)


# ---------------------------------------------------------------------------
# Batch runner
# ---------------------------------------------------------------------------

class ForecastTrackRunner:
    """Read events.json, predict each, write predictions.json."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.forecaster = _build_forecaster(cfg)
        self.research = _build_research(cfg)

    def run(self, events_path: str | Path, output_path: str | Path) -> dict[str, Any]:
        events_path = Path(events_path)
        output_path = Path(output_path)
        with events_path.open() as f:
            events = json.load(f)
        if not isinstance(events, list):
            raise ValueError(f"Expected events.json to be a list, got {type(events).__name__}")

        results = []
        for i, ev in enumerate(events):
            logger.info(
                "[%d/%d] %s",
                i + 1,
                len(events),
                str(ev.get("title", ev.get("market_ticker", "?")))[:120],
            )
            try:
                resp = _predict_with_components(ev, self.forecaster, self.research)
            except Exception as exc:
                logger.exception("predict failed for event %s: %s", i, exc)
                resp = {
                    "probabilities": [
                        {"market": o, "probability": 1.0 / max(1, len(ev.get("outcomes") or ["Yes", "No"]))}
                        for o in (ev.get("outcomes") or ["Yes", "No"])
                    ],
                    "rationale": f"Fallback (uniform) due to error: {exc}",
                }
            payload = {
                "task_id": ev.get("task_id") or ev.get("market_ticker"),
                "title": ev.get("title"),
                "outcomes": ev.get("outcomes") or ["Yes", "No"],
                **resp,
            }
            results.append(payload)

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w") as f:
            json.dump(results, f, indent=2)
        logger.info("wrote %d predictions to %s", len(results), output_path)
        return {
            "n_events": len(events),
            "n_predictions": len(results),
            "output_path": str(output_path),
        }


def _cli_local_entrypoint() -> None:
    """For ``python -m sigma_prophet.arena.forecast_client < event.json``."""
    import sys

    event = json.load(sys.stdin)
    print(json.dumps(predict(event), indent=2))


if __name__ == "__main__":
    _cli_local_entrypoint()
