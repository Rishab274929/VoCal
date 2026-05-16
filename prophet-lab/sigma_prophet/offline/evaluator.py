"""Offline evaluator.

Loads a resolved events file (compatible with ``ai-prophet-datasets``
sample-resolved shape), runs the ensemble forecaster against each event,
and prints a per-event + aggregate Brier score so judges can verify
calibration locally without hitting the arena server.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from sigma_prophet.arena.forecast_client import _build_forecaster, _build_research, _predict_with_components
from sigma_prophet.config import Config, load_config
from sigma_prophet.prediction.calibration import brier_score, log_score

logger = logging.getLogger(__name__)


@dataclass
class EvalReport:
    n_events: int
    n_scored: int
    mean_brier: float
    mean_logloss: float
    per_event: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "n_events": self.n_events,
            "n_scored": self.n_scored,
            "mean_brier": self.mean_brier,
            "mean_logloss": self.mean_logloss,
            "per_event": self.per_event,
        }


def _resolved_outcome_set(resolved: Any) -> set[str]:
    """Normalize the ``resolved_outcome.value`` field to a set of strings."""
    if resolved is None:
        return set()
    if isinstance(resolved, dict):
        value = resolved.get("value")
    else:
        value = resolved
    if isinstance(value, str):
        return {value}
    if isinstance(value, list):
        return {str(v) for v in value}
    return set()


class OfflineEvaluator:
    """Run the full pipeline against a resolved dataset and score it."""

    def __init__(self, cfg: Config | None = None):
        self.cfg = cfg or load_config()
        self.forecaster = _build_forecaster(self.cfg)
        # disable research by default for evaluation determinism
        self.research = None

    def evaluate(
        self,
        events_path: str | Path,
        *,
        limit: int | None = None,
        with_research: bool = False,
        output_path: str | Path | None = None,
    ) -> EvalReport:
        events_path = Path(events_path)
        with events_path.open() as f:
            events = json.load(f)
        if not isinstance(events, list):
            raise ValueError("events file must be a JSON list")

        if with_research:
            self.research = _build_research(self.cfg)

        if limit is not None:
            events = events[:limit]

        per_event: list[dict[str, Any]] = []
        briers: list[float] = []
        loglosses: list[float] = []
        for i, ev in enumerate(events):
            outcomes = ev.get("outcomes") or ["Yes", "No"]
            try:
                result = _predict_with_components(ev, self.forecaster, self.research)
            except Exception as exc:
                logger.warning("predict failed for %s: %s", ev.get("task_id"), exc)
                continue

            probs_map = {p["market"]: p["probability"] for p in result["probabilities"]}
            ordered_probs = [float(probs_map.get(o, 0.0)) for o in outcomes]

            resolved = _resolved_outcome_set(ev.get("resolved_outcome"))
            if not resolved:
                logger.info("[%d/%d] unresolved task, skipping", i + 1, len(events))
                continue

            one_hot = [1 if o in resolved else 0 for o in outcomes]
            b = brier_score(ordered_probs, one_hot)
            ll = log_score(ordered_probs, one_hot)
            briers.append(b)
            loglosses.append(ll)
            per_event.append(
                {
                    "task_id": ev.get("task_id"),
                    "title": ev.get("title", "")[:120],
                    "outcomes": outcomes,
                    "probabilities": ordered_probs,
                    "resolved": list(resolved),
                    "brier": b,
                    "logloss": ll,
                }
            )
            logger.info(
                "[%d/%d] brier=%.4f log=%.4f  %s",
                i + 1,
                len(events),
                b,
                ll,
                ev.get("title", "")[:80],
            )

        n_scored = len(briers)
        report = EvalReport(
            n_events=len(events),
            n_scored=n_scored,
            mean_brier=(sum(briers) / n_scored) if n_scored else 0.0,
            mean_logloss=(sum(loglosses) / n_scored) if n_scored else 0.0,
            per_event=per_event,
        )

        if output_path is not None:
            output_path = Path(output_path)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            with output_path.open("w") as f:
                json.dump(report.to_dict(), f, indent=2)
            logger.info("wrote eval report to %s", output_path)
        return report
