"""Forecaster + ensemble with a stub LLM client."""

from __future__ import annotations

import json

import pytest

from sigma_prophet.config import CalibrationConfig, ModelSpec
from sigma_prophet.prediction.ensemble import EnsembleForecaster
from sigma_prophet.prediction.forecaster import (
    ClaudeForecaster,
    LLMForecaster,
    _coerce_probabilities,
)
from sigma_prophet.prediction.llm_client import ChatResponse


class StubLLMClient:
    """Mimics ``LLMClient.chat()``. Pop a canned response per call."""

    def __init__(self, responses: list[str]):
        self.responses = list(responses)
        self.calls: list[dict] = []

    def chat(self, model: str, messages, *, max_tokens: int = 2000, temperature: float = 0.2, extra_body=None):
        self.calls.append({"model": model, "messages": messages, "max_tokens": max_tokens})
        text = self.responses.pop(0) if self.responses else self.responses[-1]
        return ChatResponse(
            content=text,
            model=model,
            finish_reason="stop",
            usage={"total_tokens": 0},
            raw={},
        )


def test_coerce_probabilities_handles_dict_shape():
    data = {"probabilities": {"Yes": 0.7, "No": 0.3}}
    out = _coerce_probabilities(data, ["Yes", "No"])
    assert out == {"Yes": 0.7, "No": 0.3}


def test_coerce_probabilities_handles_list_shape():
    data = {"probabilities": [{"market": "A", "probability": 0.4}, {"market": "B", "probability": 0.6}]}
    out = _coerce_probabilities(data, ["A", "B"])
    assert out == {"A": 0.4, "B": 0.6}


def test_coerce_probabilities_handles_percentage_outputs():
    data = {"probabilities": [{"market": "A", "probability": 70}, {"market": "B", "probability": 30}]}
    out = _coerce_probabilities(data, ["A", "B"])
    assert out["A"] == pytest.approx(0.7)
    assert out["B"] == pytest.approx(0.3)


def test_coerce_probabilities_case_insensitive_match():
    data = {"probabilities": [{"market": "yes", "probability": 0.6}, {"market": "NO", "probability": 0.4}]}
    out = _coerce_probabilities(data, ["Yes", "No"])
    assert out["Yes"] == pytest.approx(0.6)
    assert out["No"] == pytest.approx(0.4)


def test_claude_alias_still_resolvable():
    # Back-compat: old code that imported ClaudeForecaster should still work.
    assert ClaudeForecaster is LLMForecaster


def test_llm_forecaster_with_stub_client():
    spec = ModelSpec(name="GLM-5.1", provider="wafer", weight=1.0, temperature=0.0)
    stub_text = json.dumps({"probabilities": {"Yes": 0.6, "No": 0.4}, "rationale": "stubbed"})
    client = StubLLMClient(responses=[stub_text])

    forecaster = LLMForecaster(spec=spec, client=client)
    result = forecaster.forecast(
        title="Will the Bears win?",
        outcomes=["Yes", "No"],
    )
    assert result.probabilities == {"Yes": 0.6, "No": 0.4}
    assert result.rationale == "stubbed"
    assert result.model == "GLM-5.1"
    assert result.metadata["provider"] == "wafer"
    assert client.calls, "stub client should have been called"


def test_llm_forecaster_falls_back_on_invalid_json():
    spec = ModelSpec(name="GLM-5.1", provider="wafer")
    client = StubLLMClient(responses=["this is not json at all"])
    forecaster = LLMForecaster(spec=spec, client=client)
    result = forecaster.forecast(title="x", outcomes=["A", "B", "C"])
    assert result.probabilities == {
        "A": pytest.approx(1 / 3),
        "B": pytest.approx(1 / 3),
        "C": pytest.approx(1 / 3),
    }
    assert "Fallback" in result.rationale


def test_ensemble_averages_two_heads_across_providers():
    spec1 = ModelSpec(name="GLM-5.1", provider="wafer", weight=1.0)
    spec2 = ModelSpec(name="anthropic/claude-sonnet-4.5", provider="openrouter", weight=1.0)
    payload1 = json.dumps({"probabilities": {"Yes": 0.8, "No": 0.2}, "rationale": "wafer says yes"})
    payload2 = json.dumps({"probabilities": {"Yes": 0.4, "No": 0.6}, "rationale": "openrouter says no"})
    client = StubLLMClient(responses=[payload1, payload2])

    calib = CalibrationConfig(shrink_to_prior=0.0, min_prob=0.0, max_prob=1.0)
    ensemble = EnsembleForecaster.__new__(EnsembleForecaster)
    ensemble.heads = [
        LLMForecaster(spec=spec1, client=client),
        LLMForecaster(spec=spec2, client=client),
    ]
    ensemble.weights = [0.5, 0.5]
    ensemble.calibration = calib

    result = ensemble.forecast(title="Q?", outcomes=["Yes", "No"])
    assert result.probabilities["Yes"] == pytest.approx(0.6, abs=1e-6)
    assert result.probabilities["No"] == pytest.approx(0.4, abs=1e-6)
    assert "wafer says yes" in result.rationale
    assert "openrouter says no" in result.rationale
