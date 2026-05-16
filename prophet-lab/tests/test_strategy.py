"""Kelly strategy + risk budget."""

from __future__ import annotations

import pytest

from sigma_prophet.config import TradingConfig
from sigma_prophet.trading.risk import PositionView, RiskBudget, RiskState
from sigma_prophet.trading.strategy import (
    KellyStrategy,
    expected_edge,
    fractional_kelly,
    market_implied_prob,
)


def _cfg(**overrides) -> TradingConfig:
    cfg = TradingConfig(
        kelly_fraction=0.25,
        min_edge=0.05,
        min_shares=1.0,
        max_shares_per_trade=200.0,
        max_notional_per_market=1000.0,
        max_gross_exposure=10000.0,
        max_open_positions=30,
        max_trades_per_tick=20,
        market_prior_weight=0.0,
        starting_cash=10000.0,
    )
    for k, v in overrides.items():
        setattr(cfg, k, v)
    return cfg


def test_market_implied_prob_mid():
    assert market_implied_prob(0.4, 0.5) == pytest.approx(0.45)


def test_expected_edge_picks_yes():
    side, edge, entry = expected_edge(0.7, 0.4, 0.5)
    assert side == "YES"
    assert edge == pytest.approx(0.2)
    assert entry == 0.5


def test_expected_edge_picks_no():
    side, edge, entry = expected_edge(0.2, 0.4, 0.5)
    assert side == "NO"
    # NO edge = (1 - 0.2) - (1 - 0.4) = 0.2
    assert edge == pytest.approx(0.2)
    # NO entry = 1 - best_bid
    assert entry == pytest.approx(0.6)


def test_expected_edge_none_when_no_edge():
    side, _, _ = expected_edge(0.45, 0.4, 0.5)
    assert side is None


def test_fractional_kelly_zero_when_no_edge():
    assert fractional_kelly(0.4, 0.5, 0.25) == 0.0


def test_fractional_kelly_scales_by_fraction():
    full = fractional_kelly(0.7, 0.5, 1.0)
    quarter = fractional_kelly(0.7, 0.5, 0.25)
    assert quarter == pytest.approx(full * 0.25)
    # f* = (0.7 - 0.5) / (1 - 0.5) = 0.4
    assert full == pytest.approx(0.4)


def test_strategy_hold_when_edge_below_threshold():
    cfg = _cfg(min_edge=0.10)
    strat = KellyStrategy(cfg)
    decision = strat.decide(
        market_id="m1", p_yes=0.55, best_bid=0.49, best_ask=0.50, bankroll=10000
    )
    assert decision is None


def test_strategy_buys_yes_with_clear_edge():
    cfg = _cfg(min_edge=0.05)
    strat = KellyStrategy(cfg)
    decision = strat.decide(
        market_id="m1", p_yes=0.75, best_bid=0.40, best_ask=0.50, bankroll=10000
    )
    assert decision is not None
    assert decision.side == "YES"
    assert decision.action == "BUY"
    assert decision.shares >= cfg.min_shares
    assert decision.price == pytest.approx(0.50)


def test_strategy_respects_per_market_notional_cap():
    cfg = _cfg(max_notional_per_market=100.0, max_shares_per_trade=10_000)
    budget = RiskBudget(
        max_open_positions=cfg.max_open_positions,
        max_trades_per_tick=cfg.max_trades_per_tick,
        max_notional_per_market=cfg.max_notional_per_market,
        max_gross_exposure=cfg.max_gross_exposure,
        min_shares=cfg.min_shares,
        max_shares_per_trade=cfg.max_shares_per_trade,
    )
    state = RiskState(budget=budget, cash=10000)
    strat = KellyStrategy(cfg)
    decision = strat.decide(
        market_id="m1",
        p_yes=0.9,
        best_bid=0.4,
        best_ask=0.5,
        bankroll=10000,
        state=state,
    )
    assert decision is not None
    assert decision.shares * decision.price <= cfg.max_notional_per_market + 1e-6


def test_risk_state_blocks_when_trade_count_exhausted():
    cfg = _cfg(max_trades_per_tick=1)
    budget = RiskBudget(
        max_open_positions=cfg.max_open_positions,
        max_trades_per_tick=cfg.max_trades_per_tick,
        max_notional_per_market=cfg.max_notional_per_market,
        max_gross_exposure=cfg.max_gross_exposure,
        min_shares=cfg.min_shares,
        max_shares_per_trade=cfg.max_shares_per_trade,
    )
    state = RiskState(budget=budget, cash=10000)
    state.commit("m0", "YES", 10, 0.5)
    strat = KellyStrategy(cfg)
    decision = strat.decide(
        market_id="m1", p_yes=0.9, best_bid=0.4, best_ask=0.5, bankroll=10000, state=state
    )
    assert decision is None


def test_risk_state_blocks_when_open_position_cap_hit():
    cfg = _cfg(max_open_positions=1)
    budget = RiskBudget(
        max_open_positions=cfg.max_open_positions,
        max_trades_per_tick=cfg.max_trades_per_tick,
        max_notional_per_market=cfg.max_notional_per_market,
        max_gross_exposure=cfg.max_gross_exposure,
        min_shares=cfg.min_shares,
        max_shares_per_trade=cfg.max_shares_per_trade,
    )
    state = RiskState(budget=budget, cash=10000)
    state.open_positions[("m0", "YES")] = PositionView("m0", "YES", 5, 0.5)
    strat = KellyStrategy(cfg)
    decision = strat.decide(
        market_id="m1", p_yes=0.9, best_bid=0.4, best_ask=0.5, bankroll=10000, state=state
    )
    assert decision is None


def test_market_prior_shrinkage_suppresses_extreme_edge():
    cfg = _cfg(market_prior_weight=0.9)  # heavy shrinkage toward market
    strat = KellyStrategy(cfg)
    decision = strat.decide(
        market_id="m1", p_yes=0.99, best_bid=0.49, best_ask=0.50, bankroll=10000
    )
    # With 90% shrinkage, blended p moves to ~0.54 → edge well under min_edge=0.05
    assert decision is None
