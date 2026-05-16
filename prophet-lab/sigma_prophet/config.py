"""Configuration loader for SigmaProphet.

Pulls values from environment, an optional YAML file, and constructor
overrides. Environment wins for secrets; YAML wins for tunables.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.yaml"


@dataclass
class ModelSpec:
    """One LLM head in the ensemble."""

    name: str
    provider: str = "wafer"   # wafer | openrouter | openai
    weight: float = 1.0
    temperature: float = 0.2
    max_tokens: int = 2000
    base_url: str | None = None  # override the provider's default endpoint


@dataclass
class ResearchConfig:
    """Web search + LLM research settings."""

    enabled: bool = True
    backend: str = "brave"  # brave | tavily | none
    max_queries: int = 4
    max_results_per_query: int = 5
    timeout_sec: int = 25


@dataclass
class TradingConfig:
    """Trading strategy + risk limits."""

    kelly_fraction: float = 0.25
    min_edge: float = 0.05
    min_shares: float = 1.0
    max_shares_per_trade: float = 200.0
    max_notional_per_market: float = 1000.0
    max_gross_exposure: float = 10000.0
    max_open_positions: int = 30
    max_trades_per_tick: int = 20
    market_prior_weight: float = 0.35
    starting_cash: float = 10000.0
    skip_when_close_to_resolution_sec: int = 0


@dataclass
class ForecastConfig:
    """Forecast (probability-only) track settings."""

    dataset: str = "sample-sports"
    output_path: str = "outputs/predictions.json"
    timeout_per_event_sec: int = 180


@dataclass
class CalibrationConfig:
    """Calibration / shrinkage parameters."""

    shrink_to_prior: float = 0.10
    min_prob: float = 0.02
    max_prob: float = 0.98
    log_odds_smoothing: float = 0.0


@dataclass
class Config:
    """Top-level config."""

    wafer_api_key: str = ""
    openrouter_api_key: str = ""
    openai_api_key: str = ""
    brave_api_key: str = ""
    tavily_api_key: str = ""
    pa_server_url: str = "https://api.aiprophet.dev"
    pa_server_api_key: str = ""
    slug: str = "sigma-prophet"
    n_ticks: int = 96
    models: list[ModelSpec] = field(default_factory=list)
    research: ResearchConfig = field(default_factory=ResearchConfig)
    trading: TradingConfig = field(default_factory=TradingConfig)
    forecast: ForecastConfig = field(default_factory=ForecastConfig)
    calibration: CalibrationConfig = field(default_factory=CalibrationConfig)
    log_level: str = "INFO"

    def to_dict(self) -> dict[str, Any]:
        """Serializable dict (without secrets)."""
        return {
            "slug": self.slug,
            "n_ticks": self.n_ticks,
            "models": [
                {
                    "name": m.name,
                    "provider": m.provider,
                    "weight": m.weight,
                    "temperature": m.temperature,
                }
                for m in self.models
            ],
            "research": {
                "enabled": self.research.enabled,
                "backend": self.research.backend,
                "max_queries": self.research.max_queries,
            },
            "trading": {
                "kelly_fraction": self.trading.kelly_fraction,
                "min_edge": self.trading.min_edge,
                "max_notional_per_market": self.trading.max_notional_per_market,
            },
            "calibration": {
                "shrink_to_prior": self.calibration.shrink_to_prior,
                "min_prob": self.calibration.min_prob,
                "max_prob": self.calibration.max_prob,
            },
        }


def _default_models() -> list[ModelSpec]:
    """Default ensemble. Wafer-only for cost & speed; OpenRouter is opt-in.

    GLM-5.1 is the workhorse — fast and follows JSON well. Qwen3.5 is a heavy
    reasoning model used as a second opinion with a larger token budget.
    """
    return [
        ModelSpec(name="GLM-5.1", provider="wafer", weight=2.0, temperature=0.2, max_tokens=2000),
        ModelSpec(name="Qwen3.5-397B-A17B", provider="wafer", weight=1.0, temperature=0.2, max_tokens=4000),
    ]


def _read_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open() as f:
        data = yaml.safe_load(f) or {}
    return data


def load_config(yaml_path: str | Path | None = None) -> Config:
    """Load config from YAML + env. Env wins for secrets; YAML wins elsewhere."""
    path = Path(yaml_path) if yaml_path else DEFAULT_CONFIG_PATH
    data = _read_yaml(path)

    cfg = Config()

    # secrets always come from env
    cfg.wafer_api_key = os.environ.get("WAFER_API_KEY", "")
    cfg.openrouter_api_key = os.environ.get("OPENROUTER_API_KEY", "")
    cfg.openai_api_key = os.environ.get("OPENAI_API_KEY", "")
    cfg.brave_api_key = os.environ.get("BRAVE_API_KEY", "")
    cfg.tavily_api_key = os.environ.get("TAVILY_API_KEY", "")
    cfg.pa_server_api_key = os.environ.get("PA_SERVER_API_KEY", "")
    cfg.pa_server_url = os.environ.get("PA_SERVER_URL", cfg.pa_server_url)

    cfg.slug = data.get("slug") or os.environ.get("PROPHET_SLUG", cfg.slug)
    cfg.n_ticks = int(data.get("n_ticks", cfg.n_ticks))
    cfg.log_level = data.get("log_level", cfg.log_level)

    models_data = data.get("models")
    if models_data:
        cfg.models = [
            ModelSpec(
                name=m["name"],
                provider=str(m.get("provider", "wafer")),
                weight=float(m.get("weight", 1.0)),
                temperature=float(m.get("temperature", 0.2)),
                max_tokens=int(m.get("max_tokens", 2000)),
                base_url=m.get("base_url"),
            )
            for m in models_data
        ]
    else:
        cfg.models = _default_models()

    research_data = data.get("research", {})
    cfg.research = ResearchConfig(
        enabled=bool(research_data.get("enabled", cfg.research.enabled)),
        backend=research_data.get("backend", cfg.research.backend),
        max_queries=int(research_data.get("max_queries", cfg.research.max_queries)),
        max_results_per_query=int(
            research_data.get("max_results_per_query", cfg.research.max_results_per_query)
        ),
        timeout_sec=int(research_data.get("timeout_sec", cfg.research.timeout_sec)),
    )

    trading_data = data.get("trading", {})
    cfg.trading = TradingConfig(
        kelly_fraction=float(trading_data.get("kelly_fraction", cfg.trading.kelly_fraction)),
        min_edge=float(trading_data.get("min_edge", cfg.trading.min_edge)),
        min_shares=float(trading_data.get("min_shares", cfg.trading.min_shares)),
        max_shares_per_trade=float(
            trading_data.get("max_shares_per_trade", cfg.trading.max_shares_per_trade)
        ),
        max_notional_per_market=float(
            trading_data.get("max_notional_per_market", cfg.trading.max_notional_per_market)
        ),
        max_gross_exposure=float(
            trading_data.get("max_gross_exposure", cfg.trading.max_gross_exposure)
        ),
        max_open_positions=int(
            trading_data.get("max_open_positions", cfg.trading.max_open_positions)
        ),
        max_trades_per_tick=int(
            trading_data.get("max_trades_per_tick", cfg.trading.max_trades_per_tick)
        ),
        market_prior_weight=float(
            trading_data.get("market_prior_weight", cfg.trading.market_prior_weight)
        ),
        starting_cash=float(trading_data.get("starting_cash", cfg.trading.starting_cash)),
        skip_when_close_to_resolution_sec=int(
            trading_data.get(
                "skip_when_close_to_resolution_sec",
                cfg.trading.skip_when_close_to_resolution_sec,
            )
        ),
    )

    forecast_data = data.get("forecast", {})
    cfg.forecast = ForecastConfig(
        dataset=forecast_data.get("dataset", cfg.forecast.dataset),
        output_path=forecast_data.get("output_path", cfg.forecast.output_path),
        timeout_per_event_sec=int(
            forecast_data.get("timeout_per_event_sec", cfg.forecast.timeout_per_event_sec)
        ),
    )

    calib_data = data.get("calibration", {})
    cfg.calibration = CalibrationConfig(
        shrink_to_prior=float(
            calib_data.get("shrink_to_prior", cfg.calibration.shrink_to_prior)
        ),
        min_prob=float(calib_data.get("min_prob", cfg.calibration.min_prob)),
        max_prob=float(calib_data.get("max_prob", cfg.calibration.max_prob)),
        log_odds_smoothing=float(
            calib_data.get("log_odds_smoothing", cfg.calibration.log_odds_smoothing)
        ),
    )

    return cfg
