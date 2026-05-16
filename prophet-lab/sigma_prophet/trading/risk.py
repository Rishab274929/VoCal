"""Risk budget tracking for the trade loop.

Mirrors the server-side ruleset so we don't waste API calls on intents
that will be rejected. Authoritative limits live in
``ai_prophet_core.ruleset``; this is a conservative shadow copy.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class PositionView:
    """Simple view of an open position, side-keyed."""

    market_id: str
    side: str
    shares: float
    avg_entry_price: float


@dataclass
class RiskBudget:
    """Trading constraints applied client-side."""

    max_open_positions: int = 30
    max_trades_per_tick: int = 20
    max_notional_per_market: float = 1000.0
    max_gross_exposure: float = 10000.0
    min_shares: float = 1.0
    max_shares_per_trade: float = 200.0


@dataclass
class RiskState:
    """Running totals during a single tick. Mutated as intents are accepted."""

    budget: RiskBudget
    cash: float
    gross_exposure: float = 0.0
    open_positions: dict[tuple[str, str], PositionView] = field(default_factory=dict)
    notional_by_market: dict[str, float] = field(default_factory=dict)
    trades_this_tick: int = 0

    @classmethod
    def from_portfolio(
        cls,
        budget: RiskBudget,
        cash: float,
        positions: list[PositionView],
    ) -> "RiskState":
        state = cls(budget=budget, cash=cash)
        for p in positions:
            state.open_positions[(p.market_id, p.side)] = p
            notional = abs(p.shares) * p.avg_entry_price
            state.notional_by_market[p.market_id] = (
                state.notional_by_market.get(p.market_id, 0.0) + notional
            )
            state.gross_exposure += notional
        return state

    def remaining_market_capacity(self, market_id: str) -> float:
        used = self.notional_by_market.get(market_id, 0.0)
        return max(0.0, self.budget.max_notional_per_market - used)

    def remaining_gross_capacity(self) -> float:
        return max(0.0, self.budget.max_gross_exposure - self.gross_exposure)

    def can_open_new_position(self, market_id: str, side: str) -> bool:
        if (market_id, side) in self.open_positions:
            return True
        return len(self.open_positions) < self.budget.max_open_positions

    def can_trade(self) -> bool:
        return self.trades_this_tick < self.budget.max_trades_per_tick

    def commit(self, market_id: str, side: str, shares: float, price: float) -> None:
        notional = abs(shares) * max(price, 0.0)
        self.trades_this_tick += 1
        self.gross_exposure += notional
        self.notional_by_market[market_id] = self.notional_by_market.get(market_id, 0.0) + notional
        key = (market_id, side)
        existing = self.open_positions.get(key)
        if existing is None:
            self.open_positions[key] = PositionView(
                market_id=market_id,
                side=side,
                shares=shares,
                avg_entry_price=price,
            )
        else:
            total_shares = existing.shares + shares
            if total_shares <= 0:
                self.open_positions.pop(key, None)
            else:
                blended = (
                    existing.shares * existing.avg_entry_price + shares * price
                ) / total_shares
                self.open_positions[key] = PositionView(
                    market_id=market_id,
                    side=side,
                    shares=total_shares,
                    avg_entry_price=blended,
                )
