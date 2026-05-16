"""Offline evaluator: mocks the forecaster and verifies Brier math."""

from __future__ import annotations

import json
from pathlib import Path

from sigma_prophet.config import load_config
from sigma_prophet.offline.evaluator import OfflineEvaluator, _resolved_outcome_set


def test_resolved_outcome_set_string():
    assert _resolved_outcome_set({"value": "Alice"}) == {"Alice"}


def test_resolved_outcome_set_list():
    assert _resolved_outcome_set({"value": ["Alice", "Bob"]}) == {"Alice", "Bob"}


def test_resolved_outcome_set_none():
    assert _resolved_outcome_set(None) == set()


def _write_events(path: Path, events: list[dict]) -> None:
    with path.open("w") as f:
        json.dump(events, f)


def test_evaluator_scores_resolved_events(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-test")
    events = [
        {
            "task_id": "t1",
            "title": "Will A happen?",
            "outcomes": ["A", "B"],
            "resolved_outcome": {"value": ["A"]},
        },
        {
            "task_id": "t2",
            "title": "Will A happen?",
            "outcomes": ["A", "B"],
            "resolved_outcome": {"value": ["B"]},
        },
    ]
    events_path = tmp_path / "events.json"
    _write_events(events_path, events)

    cfg = load_config(tmp_path / "missing-config.yaml")
    evaluator = OfflineEvaluator(cfg=cfg)

    def fake_predict(event, *_args, **_kwargs):
        # Always predict 0.7/0.3 for A/B
        return {
            "probabilities": [
                {"market": "A", "probability": 0.7},
                {"market": "B", "probability": 0.3},
            ],
            "rationale": "stub",
        }

    import sigma_prophet.offline.evaluator as evmod
    monkeypatch.setattr(evmod, "_predict_with_components", fake_predict)

    report = evaluator.evaluate(events_path)
    assert report.n_scored == 2
    # Event 1: prob 0.7 for A which won → Brier = ((0.7-1)^2 + (0.3-0)^2)/2 = 0.09
    # Event 2: prob 0.7 for A which lost → Brier = ((0.7-0)^2 + (0.3-1)^2)/2 = 0.49
    # Mean = 0.29
    assert abs(report.mean_brier - 0.29) < 1e-6


def test_evaluator_skips_unresolved(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-test")
    events = [
        {"task_id": "t1", "title": "?", "outcomes": ["A", "B"], "resolved_outcome": None},
    ]
    events_path = tmp_path / "events.json"
    _write_events(events_path, events)

    cfg = load_config(tmp_path / "missing.yaml")
    evaluator = OfflineEvaluator(cfg=cfg)

    import sigma_prophet.offline.evaluator as evmod
    monkeypatch.setattr(
        evmod,
        "_predict_with_components",
        lambda *a, **k: {
            "probabilities": [{"market": "A", "probability": 0.5}, {"market": "B", "probability": 0.5}],
            "rationale": "",
        },
    )

    report = evaluator.evaluate(events_path)
    assert report.n_events == 1
    assert report.n_scored == 0
