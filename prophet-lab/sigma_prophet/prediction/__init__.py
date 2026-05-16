"""Prediction module: LLM-driven probability forecasting."""

from sigma_prophet.prediction.calibration import (
    apply_calibration,
    brier_score,
    log_score,
    shrink_to_prior,
)
from sigma_prophet.prediction.ensemble import EnsembleForecaster
from sigma_prophet.prediction.forecaster import (
    ClaudeForecaster,
    ForecastResult,
    LLMForecaster,
)
from sigma_prophet.prediction.llm_client import LLMClient, LLMError

__all__ = [
    "LLMForecaster",
    "ClaudeForecaster",
    "EnsembleForecaster",
    "ForecastResult",
    "LLMClient",
    "LLMError",
    "apply_calibration",
    "shrink_to_prior",
    "brier_score",
    "log_score",
]
