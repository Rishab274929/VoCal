"""Smoke test: every public module imports cleanly."""

from __future__ import annotations


def test_top_level_imports():
    import sigma_prophet  # noqa: F401
    import sigma_prophet.agent  # noqa: F401
    import sigma_prophet.cli  # noqa: F401
    import sigma_prophet.config  # noqa: F401
    import sigma_prophet.logging_utils  # noqa: F401


def test_prediction_imports():
    from sigma_prophet.prediction import (  # noqa: F401
        ClaudeForecaster,
        EnsembleForecaster,
        ForecastResult,
        apply_calibration,
        brier_score,
        log_score,
        shrink_to_prior,
    )


def test_research_imports():
    from sigma_prophet.research import (  # noqa: F401
        BraveSearch,
        EvidenceBundle,
        NullSearch,
        ResearchAgent,
        SearchResult,
        TavilySearch,
        get_search_backend,
    )


def test_trading_imports():
    from sigma_prophet.trading import (  # noqa: F401
        Decision,
        KellyStrategy,
        PositionView,
        RiskBudget,
        RiskState,
        decide_market,
        expected_edge,
        fractional_kelly,
        market_implied_prob,
    )


def test_arena_imports():
    from sigma_prophet.arena import build_app, predict_event, ForecastTrackRunner  # noqa: F401
    from sigma_prophet.arena.trade_client import TradeTrackRunner  # noqa: F401


def test_offline_imports():
    from sigma_prophet.offline import OfflineEvaluator, EvalReport  # noqa: F401
