# Architecture

Prophet Lab is structured as a small kernel of independent modules wired
together by a thin orchestrator.

```
sigma_prophet/
├── prediction/   pure: LLM → distribution + calibration
├── research/     pure: question → web evidence
├── trading/      pure: probability + quote → trade decision
├── arena/        integration: Prophet Arena adapters (forecast / trade / hosted)
├── offline/      integration: Brier/log-loss scoring
└── cli.py        orchestrator
```

Each module exports a small public surface and is unit-testable in isolation.

## Data flow

```
                    ┌─────────────────────────┐
                    │ Event / Market          │
                    │ (title, outcomes, rules)│
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┴───────────────────┐
              ▼                                      ▼
       ┌────────────┐                       ┌────────────────┐
       │ Decompose  │                       │ Direct forecast│
       │ (Claude)   │                       │ (no research)  │
       └─────┬──────┘                       └────────┬───────┘
             │                                       │
             ▼                                       │
       ┌────────────┐                                │
       │ Web search │                                │
       │ Brave/Tav  │                                │
       └─────┬──────┘                                │
             │                                       │
             ▼                                       │
       ┌────────────┐                                │
       │ Reconcile  │                                │
       │ (Claude)   │                                │
       └─────┬──────┘                                │
             │                                       │
             └───────────┐                  ┌────────┘
                         ▼                  ▼
                  ┌─────────────────────────────┐
                  │ EnsembleForecaster          │
                  │  weighted avg across heads  │
                  └────────────┬────────────────┘
                               │
                               ▼
                  ┌─────────────────────────────┐
                  │ Calibration                 │
                  │  shrink + clip + smooth     │
                  └────────────┬────────────────┘
                               │
              ┌────────────────┴─────────────────┐
              ▼                                  ▼
       ┌─────────────┐                  ┌────────────────┐
       │ Forecast    │                  │ Kelly strategy │
       │ submission  │                  │ + risk budget  │
       └─────────────┘                  └───────┬────────┘
                                                │
                                                ▼
                                         ┌────────────────┐
                                         │ Trade intents  │
                                         │ → Prophet Arena │
                                         └────────────────┘
```

## Key types

- **`ModelSpec`** — one Claude model + weight + temperature.
- **`EnsembleForecaster`** — orchestrates `ClaudeForecaster` heads, merges
  distributions, applies calibration.
- **`ResearchAgent`** — decomposes a question into search queries, runs the
  chosen backend, returns an `EvidenceBundle`.
- **`KellyStrategy`** — pure function from `(p_yes, bid, ask, bankroll)` to
  a `Decision` (BUY YES/NO N shares) honoring the risk budget.
- **`RiskState`** — running per-tick tally of exposure and trade count.
- **`TradeExecutor`** — drives the Prophet Arena tick lifecycle through
  `ai_prophet_core.arena.BenchmarkSession`.

## Why this shape

- The arena SDK already gives us a tight tick lifecycle. We don't reimplement
  it; we just provide a strategy + forecaster and let `BenchmarkSession`
  run the loop.
- Separating research from prediction means we can A/B test "ensemble alone"
  vs "ensemble + research" on the offline evaluator with a single config flip.
- The Kelly strategy is decoupled from the forecaster — if you want to swap
  in a logistic-regression baseline, you only replace the forecaster.
- All side-effecting code (HTTP, file I/O) lives in `arena/` and `cli.py`.
  Everything in `prediction/`, `trading/`, and `research/` is pure aside from
  the LLM call inside `ClaudeForecaster`, which is the natural boundary.

## Failure modes & resilience

- **Claude returns malformed JSON** → `extract_json_object` strips fences and
  trailing commas; on terminal failure the head falls back to the uniform
  distribution and logs a warning.
- **Web search fails / no API key** → `NullSearch` returns empty results;
  reconciler runs without evidence, falling back to the direct-forecast prompt.
- **Arena server flakes** → `ServerAPIClient` retries with exponential backoff
  and honors `Retry-After`. We additionally wrap our own retries around the
  LLM calls.
- **Stale lease / submission deadline** → server returns HTTP 409, we log and
  move on to the next tick (no data loss; the lease auto-expires).
- **Crash mid-run** → restart with the same `slug` and `config_hash`; the
  server returns the existing experiment and we resume on the next claim.

## Extending

- **New forecaster backend** — implement an interface with `forecast(...)`
  returning `ForecastResult` and stub it into the ensemble alongside (or
  instead of) `ClaudeForecaster`.
- **New search backend** — subclass `SearchBackend` and register it in
  `get_search_backend()`.
- **Different sizing policy** — swap `KellyStrategy` with anything implementing
  `decide(market_id, p_yes, best_bid, best_ask, bankroll, state) -> Decision | None`.
