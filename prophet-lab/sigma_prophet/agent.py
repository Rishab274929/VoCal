"""High-level agent facade.

Wraps the forecaster + research + strategy so external callers can do:

    from sigma_prophet.agent import SigmaProphetAgent
    agent = SigmaProphetAgent.from_env()
    result = agent.forecast("Will it rain in Chicago tomorrow?", ["Yes", "No"])
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from sigma_prophet.arena.forecast_client import _build_forecaster, _build_research
from sigma_prophet.config import Config, load_config
from sigma_prophet.prediction.ensemble import EnsembleForecaster, EnsembleResult
from sigma_prophet.research.evidence import ResearchAgent
from sigma_prophet.trading.strategy import Decision, KellyStrategy


@dataclass
class SigmaProphetAgent:
    """Top-level forecasting + trading facade."""

    cfg: Config
    forecaster: EnsembleForecaster
    research: ResearchAgent | None
    strategy: KellyStrategy

    @classmethod
    def from_env(cls, config_path: str | None = None) -> "SigmaProphetAgent":
        cfg = load_config(config_path)
        forecaster = _build_forecaster(cfg)
        research = _build_research(cfg)
        strategy = KellyStrategy(cfg.trading)
        return cls(cfg=cfg, forecaster=forecaster, research=research, strategy=strategy)

    def forecast(
        self,
        title: str,
        outcomes: list[str],
        *,
        rules: str | None = None,
        close_time: str | None = None,
        skip_research: bool = False,
    ) -> EnsembleResult:
        evidence = None
        if not skip_research and self.research is not None:
            bundle = self.research.gather(title, outcomes)
            evidence = bundle.to_prompt_text() or None
        return self.forecaster.forecast(
            title=title,
            outcomes=outcomes,
            rules=rules,
            close_time=close_time,
            evidence=evidence,
        )

    def decide(
        self,
        *,
        market_id: str,
        p_yes: float,
        best_bid: float,
        best_ask: float,
        bankroll: float | None = None,
    ) -> Decision | None:
        return self.strategy.decide(
            market_id=market_id,
            p_yes=p_yes,
            best_bid=best_bid,
            best_ask=best_ask,
            bankroll=bankroll if bankroll is not None else self.cfg.trading.starting_cash,
        )
