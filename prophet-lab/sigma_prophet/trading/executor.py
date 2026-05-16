"""Trade-track executor: long-lived tick loop against the Prophet Arena API.

Talks to ``ai_prophet_core.arena.BenchmarkSession``. For each tick:

  1. claim_tick
  2. load_candidates
  3. fetch portfolio (cash + positions)
  4. for each market: forecast (binary YES/NO) + Kelly decision
  5. submit_intents
  6. put_plan (audit trail)
  7. finalize + complete_tick
"""

from __future__ import annotations

import hashlib
import json
import logging
import time
from dataclasses import asdict, dataclass
from typing import Any

from sigma_prophet.config import Config
from sigma_prophet.prediction.ensemble import EnsembleForecaster
from sigma_prophet.research.evidence import ResearchAgent
from sigma_prophet.trading.risk import PositionView, RiskBudget, RiskState
from sigma_prophet.trading.strategy import Decision, KellyStrategy

logger = logging.getLogger(__name__)


@dataclass
class TickReport:
    tick_id: str
    n_candidates: int
    n_decisions: int
    n_accepted: int
    n_rejected: int
    decisions: list[dict[str, Any]]


def _build_outcomes_for_market(market: Any) -> tuple[str, list[str]]:
    """Most Kalshi-style markets are binary YES/NO."""
    return (market.question, ["Yes", "No"])


def config_hash(cfg: Config) -> str:
    payload = json.dumps(cfg.to_dict(), sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()[:16]


class TradeExecutor:
    """Coordinates the per-tick decision pipeline."""

    def __init__(
        self,
        cfg: Config,
        forecaster: EnsembleForecaster,
        research: ResearchAgent | None,
        strategy: KellyStrategy,
    ):
        self.cfg = cfg
        self.forecaster = forecaster
        self.research = research
        self.strategy = strategy

    def _portfolio_to_state(self, portfolio: Any | None) -> RiskState:
        budget = RiskBudget(
            max_open_positions=self.cfg.trading.max_open_positions,
            max_trades_per_tick=self.cfg.trading.max_trades_per_tick,
            max_notional_per_market=self.cfg.trading.max_notional_per_market,
            max_gross_exposure=self.cfg.trading.max_gross_exposure,
            min_shares=self.cfg.trading.min_shares,
            max_shares_per_trade=self.cfg.trading.max_shares_per_trade,
        )
        if portfolio is None:
            return RiskState(budget=budget, cash=self.cfg.trading.starting_cash)
        cash = float(portfolio.cash)
        positions: list[PositionView] = []
        for pos in portfolio.positions:
            positions.append(
                PositionView(
                    market_id=pos.market_id,
                    side=pos.side,
                    shares=float(pos.shares),
                    avg_entry_price=float(pos.avg_entry_price),
                )
            )
        return RiskState.from_portfolio(budget, cash, positions)

    def _evaluate_market(self, market: Any) -> tuple[float, str]:
        """Return (p_yes, rationale) for one market."""
        title, outcomes = _build_outcomes_for_market(market)
        evidence_text = ""
        if self.research is not None:
            bundle = self.research.gather(title, outcomes)
            evidence_text = bundle.to_prompt_text()
        ens = self.forecaster.forecast(
            title=title,
            outcomes=outcomes,
            evidence=evidence_text or None,
            rules=getattr(market, "description", None),
            close_time=getattr(market, "resolution_time", None) and str(market.resolution_time),
        )
        p_yes = float(ens.probabilities.get("Yes", 0.5))
        return p_yes, ens.rationale

    def decide_tick(
        self,
        markets: list[Any],
        portfolio: Any | None,
    ) -> tuple[list[Decision], RiskState, list[dict[str, Any]]]:
        state = self._portfolio_to_state(portfolio)
        decisions: list[Decision] = []
        audit: list[dict[str, Any]] = []
        bankroll = state.cash
        for market in markets:
            try:
                quote = market.quote
                best_bid = float(quote.best_bid)
                best_ask = float(quote.best_ask)
            except (AttributeError, ValueError, TypeError) as exc:
                logger.warning("skipping market %s: bad quote (%s)", market.market_id, exc)
                continue

            try:
                p_yes, rationale = self._evaluate_market(market)
            except Exception as exc:
                logger.warning("forecast failed for %s: %s", market.market_id, exc)
                continue

            decision = self.strategy.decide(
                market_id=market.market_id,
                p_yes=p_yes,
                best_bid=best_bid,
                best_ask=best_ask,
                bankroll=bankroll,
                state=state,
            )
            audit.append({
                "market_id": market.market_id,
                "question": market.question,
                "p_yes": round(p_yes, 4),
                "best_bid": best_bid,
                "best_ask": best_ask,
                "rationale": rationale,
                "decision": asdict(decision) if decision else None,
            })
            if decision is None:
                continue
            decisions.append(decision)
            state.commit(decision.market_id, decision.side, decision.shares, decision.price)

        return decisions, state, audit

    def run_loop(self, session: Any, participant_idx: int, *, max_ticks: int | None = None) -> None:
        """Drive the long-lived tick loop until experiment completes."""
        from ai_prophet_core import TradeIntentRequest  # local import keeps SDK optional

        ticks_done = 0
        while True:
            lease = session.claim_tick()
            if not lease.available:
                if lease.reason == "experiment_completed":
                    logger.info("experiment completed; exiting tick loop")
                    return
                wait = max(5, lease.retry_after_sec or 15)
                logger.info("no tick available (%s); sleeping %ds", lease.reason, wait)
                time.sleep(wait)
                continue

            tick = session.load_candidates(lease)
            lease = tick.lease
            markets = tick.candidates.markets
            portfolio = session.get_portfolio(participant_idx)
            decisions, _state, audit = self.decide_tick(markets, portfolio)

            intents: list[Any] = []
            for d in decisions:
                intents.append(
                    TradeIntentRequest(
                        market_id=d.market_id,
                        action=d.action,
                        side=d.side,
                        shares=f"{d.shares:.2f}",
                        idempotency_key="",
                    )
                )

            session.put_plan(
                lease,
                participant_idx,
                {
                    "strategy": "fractional-kelly",
                    "audit": audit,
                    "n_decisions": len(decisions),
                },
            )
            accepted, rejected = 0, 0
            if intents:
                try:
                    result = session.submit_intents(lease, participant_idx, intents)
                    accepted = result.accepted
                    rejected = result.rejected
                except Exception as exc:
                    logger.error("submit_intents failed: %s", exc)
            session.finalize(lease, participant_idx)
            session.complete_tick(lease)

            logger.info(
                "tick=%s decided=%d intents=%d accepted=%d rejected=%d",
                lease.tick_id,
                len(decisions),
                len(intents),
                accepted,
                rejected,
            )
            ticks_done += 1
            if max_ticks is not None and ticks_done >= max_ticks:
                logger.info("max_ticks=%d reached; exiting", max_ticks)
                return
