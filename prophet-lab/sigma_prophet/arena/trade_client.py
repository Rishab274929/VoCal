"""Trade-track adapter: wires SigmaProphet into the Prophet Arena tick loop."""

from __future__ import annotations

import logging

from sigma_prophet.arena.forecast_client import _build_forecaster, _build_research
from sigma_prophet.config import Config
from sigma_prophet.trading.executor import TradeExecutor, config_hash
from sigma_prophet.trading.strategy import KellyStrategy

logger = logging.getLogger(__name__)


class TradeTrackRunner:
    """High-level orchestrator for the Prophet Arena trade benchmark."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.forecaster = _build_forecaster(cfg)
        self.research = _build_research(cfg)
        self.strategy = KellyStrategy(cfg=cfg.trading)
        self.executor = TradeExecutor(
            cfg=cfg,
            forecaster=self.forecaster,
            research=self.research,
            strategy=self.strategy,
        )

    def run(self, *, max_ticks: int | None = None, model_label: str | None = None) -> None:
        """Start the long-lived loop. Blocks until the experiment finishes."""
        from ai_prophet_core import ServerAPIClient
        from ai_prophet_core.arena import BenchmarkSession

        api = ServerAPIClient(
            base_url=self.cfg.pa_server_url,
            api_key=self.cfg.pa_server_api_key or None,
            timeout=30,
        )
        n_ticks = max_ticks or self.cfg.n_ticks
        try:
            with BenchmarkSession(api) as session:
                session.create_experiment(
                    slug=self.cfg.slug,
                    config_hash=config_hash(self.cfg),
                    config_json=self.cfg.to_dict(),
                    n_ticks=n_ticks,
                )
                part = session.upsert_participant(
                    model=model_label or "sigma:prophet-ensemble",
                    starting_cash=self.cfg.trading.starting_cash,
                )
                logger.info(
                    "experiment=%s participant_idx=%d n_ticks=%d",
                    session.experiment_id,
                    part.participant_idx,
                    n_ticks,
                )
                self.executor.run_loop(session, part.participant_idx, max_ticks=max_ticks)
        finally:
            api.close()
