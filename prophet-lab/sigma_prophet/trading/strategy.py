"""Kelly-based sizing strategy for binary prediction markets.

Prediction-market math (each market resolves to 1 or 0):
  - BUY YES at price ``ask`` pays 1 if YES wins, 0 otherwise.
    Profit per share if YES: ``1 - ask``.  Loss per share if NO: ``ask``.
  - BUY NO at price ``1 - bid`` pays 1 if NO wins, 0 otherwise.
    Equivalent to a YES short at ``bid``.

Kelly fraction for a binary bet with our probability ``p`` and entry
price ``c`` is:
    f* = (p - c) / (1 - c)      for a "buy YES at c" bet
    f* = ((1-p) - (1-b)) / b    for a "buy NO at (1-b)" bet, simplified
                                back to: ((1-p) - c_no) / (1 - c_no)
We expose ``f*`` and let the caller scale by a fractional-Kelly multiplier
plus the risk-budget caps.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from typing import Literal

from sigma_prophet.config import TradingConfig
from sigma_prophet.trading.risk import RiskState

logger = logging.getLogger(__name__)

Side = Literal["YES", "NO"]
Action = Literal["BUY", "SELL"]


@dataclass(frozen=True)
class Decision:
    """One trade decision derived from a forecast vs. quote."""

    market_id: str
    action: Action
    side: Side
    shares: float
    price: float
    edge: float
    rationale: str = ""


def market_implied_prob(best_bid: float, best_ask: float) -> float:
    """Mid-of-quote implied probability of YES, in [0,1].

    Prediction markets price both sides into [0,1] with bid+ask ≈ 1
    on opposite sides, so the YES mid is itself the implied probability.
    """
    if best_ask <= 0 and best_bid <= 0:
        return 0.5
    mid = 0.5 * (best_bid + best_ask)
    return min(max(mid, 0.0), 1.0)


def expected_edge(p_yes: float, best_bid: float, best_ask: float) -> tuple[Side | None, float, float]:
    """Pick the better side. Returns (side, edge, entry_price).

    Edge = our_prob - implied_prob for the side we'd buy.
    Returns side=None when no side has positive edge.
    """
    yes_edge = p_yes - best_ask
    no_edge = (1 - p_yes) - (1 - best_bid)
    if yes_edge >= no_edge and yes_edge > 0:
        return ("YES", yes_edge, best_ask)
    if no_edge > 0:
        return ("NO", no_edge, 1 - best_bid)
    return (None, max(yes_edge, no_edge), 0.0)


def fractional_kelly(p_win: float, entry_price: float, kelly_fraction: float = 0.25) -> float:
    """Kelly bet size as a fraction of bankroll.

    For a binary win/lose bet where we pay ``entry_price`` per share and
    receive 1 per share if we win, the optimal Kelly fraction of bankroll
    to allocate is::

        f* = (p*(1-c) - (1-p)*c) / (1-c) = (p - c) / (1 - c)

    The caller scales by ``kelly_fraction`` (typically 0.1 - 0.5) for
    fractional Kelly safety. Returns 0 when edge is non-positive.
    """
    if entry_price <= 0 or entry_price >= 1:
        return 0.0
    if p_win <= entry_price:
        return 0.0
    full = (p_win - entry_price) / (1 - entry_price)
    return max(0.0, full * max(0.0, kelly_fraction))


def _blend_with_market(
    p_yes: float,
    best_bid: float,
    best_ask: float,
    weight: float,
) -> float:
    """Shrink the model's p_yes toward the market-implied mid.

    Prevents over-betting against the market when our edge is borderline.
    ``weight`` in [0,1] is the fraction of mass moved toward the mid.
    """
    weight = min(max(weight, 0.0), 1.0)
    if weight <= 0:
        return p_yes
    mid = market_implied_prob(best_bid, best_ask)
    return (1 - weight) * p_yes + weight * mid


def decide_market(
    *,
    market_id: str,
    p_yes: float,
    best_bid: float,
    best_ask: float,
    bankroll: float,
    cfg: TradingConfig,
    state: RiskState | None = None,
) -> Decision | None:
    """Return a trade Decision or None to HOLD."""

    if best_ask <= 0 or best_bid <= 0 or best_bid >= best_ask:
        return None

    blended_p = _blend_with_market(p_yes, best_bid, best_ask, cfg.market_prior_weight)
    side, edge, entry = expected_edge(blended_p, best_bid, best_ask)
    if side is None or edge < cfg.min_edge:
        return None

    win_prob = blended_p if side == "YES" else 1 - blended_p
    kelly_frac = fractional_kelly(win_prob, entry, cfg.kelly_fraction)
    if kelly_frac <= 0:
        return None

    desired_notional = kelly_frac * max(bankroll, 0.0)
    if state is not None:
        market_cap = state.remaining_market_capacity(market_id)
        gross_cap = state.remaining_gross_capacity()
        desired_notional = min(desired_notional, market_cap, gross_cap, cfg.max_notional_per_market)

    if desired_notional <= 0:
        return None

    raw_shares = desired_notional / max(entry, 1e-6)
    capped_shares = min(raw_shares, cfg.max_shares_per_trade)
    if math.isnan(capped_shares):
        return None

    shares = math.floor(capped_shares * 100.0) / 100.0
    if shares < cfg.min_shares:
        return None

    if state is not None:
        if not state.can_trade():
            return None
        if not state.can_open_new_position(market_id, side):
            return None

    rationale = (
        f"p_yes={p_yes:.3f} blended={blended_p:.3f} side={side} "
        f"entry={entry:.3f} edge={edge:.3f} kelly_f={kelly_frac:.4f} "
        f"shares={shares:.2f}"
    )
    return Decision(
        market_id=market_id,
        action="BUY",
        side=side,
        shares=shares,
        price=entry,
        edge=edge,
        rationale=rationale,
    )


@dataclass
class KellyStrategy:
    """Convenience facade for the trade executor."""

    cfg: TradingConfig

    def decide(
        self,
        *,
        market_id: str,
        p_yes: float,
        best_bid: float,
        best_ask: float,
        bankroll: float,
        state: RiskState | None = None,
    ) -> Decision | None:
        return decide_market(
            market_id=market_id,
            p_yes=p_yes,
            best_bid=best_bid,
            best_ask=best_ask,
            bankroll=bankroll,
            cfg=self.cfg,
            state=state,
        )
