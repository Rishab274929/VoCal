# Methodology

How and why Prophet Lab makes the choices it does.

## 1. The scoring function dictates strategy

Prophet Arena ranks LLMs on two metrics:

1. **Mean Brier score** — `mean over events of mean((p_i - o_i)^2)`
2. **Average Return (AVER)** — long-run return from betting based on the LLM's
   probabilities under a fixed-budget CRRA-utility strategy.

Brier is a **proper scoring rule**, which means honest reporting is the
profit-maximizing strategy: any deviation from your true belief raises your
expected Brier. AVER, by contrast, rewards **edge** — the gap between your
probability and the market-implied probability.

These two metrics favor slightly different behaviors:

- Brier favors **honest calibration**. Don't be overconfident.
- AVER favors **decisive edge**. Don't be mealy-mouthed when you have a real
  signal.

Prophet Lab targets both with a tunable trade-off in the calibration block.

## 2. Ensemble across Claude models

We weight three Claude models (Opus 4.5, Sonnet 4.5, Haiku 4.5) and average
their distributions on the simplex. Why ensemble at all?

- **Independent-error averaging.** Different models hallucinate in different
  ways; averaging shrinks variance without bias.
- **Brier is sub-additive in expectation.** `E[Brier(avg(p_i))] ≤
  avg(E[Brier(p_i)])` by Jensen — strictly better than any single model on
  average, with equality only if all heads are identical.

Weights are not equal — Opus carries more weight because it benchmarks higher
on reasoning tasks. We renormalize so the weights always sum to 1.

We average **distributions** rather than **log-odds**. Both are reasonable;
distribution-averaging is faster to implement and slightly more conservative
(less prone to extreme outputs when one head disagrees strongly).

## 3. Two-stage research

For each event:

1. **Decompose** — one Claude call asks for 2-4 search queries that would
   uncover the most decision-relevant evidence.
2. **Search** — each query goes to the chosen web search backend; results are
   de-duplicated by URL.
3. **Reconcile** — the full ensemble re-forecasts the event with the
   web-search snippets pasted into the prompt.

Why decompose? Direct-search-with-the-title misses adversarial evidence
("Will X happen" tends to return articles arguing X will happen). Asking for
queries that surface **both directions** halves this bias in practice.

Why reconcile with the same ensemble? The evidence is a strict information
upgrade — we don't want to throw away the prior reasoning, just condition
on the new data. The reconciliation prompt explicitly tells the model to
cite specific snippets, which surfaces calibration-relevant facts.

## 4. Calibration

Three sequential adjustments applied to the ensemble output:

1. **Shrinkage toward a prior.** Linear interpolation toward the uniform
   distribution (or, in trade mode, the market-implied distribution) at a
   small weight (default 0.10). This bounds overconfidence without flattening
   real signal.
2. **Log-odds smoothing (optional).** For each probability `p`, compute
   `logit(p) * (1 - α)` then sigmoid back. Pulls extreme tails toward 0.5
   while leaving moderate probabilities mostly untouched. Off by default;
   useful for very dense ensembles.
3. **Clamping.** Floor at `min_prob = 0.02`, cap at `max_prob = 0.98`, then
   renormalize. Stops a single near-zero/one outcome from torching Brier on
   an unexpected resolution.

The defaults are tuned for the public sample-resolved dataset; an offline
gridsearch is left as an exercise in `notebooks/`.

## 5. Kelly sizing

For the trade track, the strategy decides — per market, per tick — whether to
buy YES or NO and how many shares to buy.

### Picking the side

For a market quoting `best_bid` / `best_ask`:

- **YES edge** = `p_yes - best_ask` (we'd pay `best_ask` to buy YES, win 1 if
  YES occurs with probability `p_yes`).
- **NO edge** = `(1 - p_yes) - (1 - best_bid)` = `best_bid - p_yes`.

Pick the higher-edge side; if both edges are below `trading.min_edge` (default
5pp), HOLD.

### Sizing

Classic Kelly for a binary bet at entry price `c` with win probability `p`:

```
f* = (p - c) / (1 - c)
```

We use **fractional Kelly** — multiply `f*` by `kelly_fraction = 0.25` (quarter
Kelly). Quarter-Kelly cuts the chance of catastrophic drawdown while keeping
~94% of full-Kelly's expected growth. Standard ladder-of-bets trade-off.

### Market-implied shrinkage

Before computing edge, we shrink `p_yes` toward the **market mid** by
`market_prior_weight` (default 0.35). This guards against scenarios where the
ensemble disagrees strongly with the market — usually the market knows
something we don't. Setting `market_prior_weight = 0` disables this; `1.0`
makes the agent perfectly market-neutral (never trades). 0.3-0.4 is the sweet
spot in our sample-resolved backtests.

### Risk caps

Mirror the server-side ruleset:

- Per-market notional ≤ $1,000
- Gross exposure ≤ $10,000
- ≤ 30 open positions
- ≤ 20 trades per tick

Caps are enforced client-side first so we don't waste API calls on intents
that the server will reject.

## 6. Failure-mode philosophy

The pipeline never raises in production. Every failure path has a defined
fallback:

- LLM JSON parse failure → uniform distribution + warning log
- Search failure → continue with empty evidence
- Network blip during tick lifecycle → SDK retries, then we re-claim on the
  next tick
- Server returns 409 (deadline passed) → log + skip to next tick

A `--max-ticks 4` smoke run completes in ~12 minutes without any external
intervention.

## 7. Open questions / future work

- **Calibrated weighting** — replace static ensemble weights with online
  Brier-optimal weights, updated after each scored event.
- **Isotonic post-hoc calibration** — fit a Platt or isotonic curve on the
  resolved sample and apply it as a last calibration step.
- **Sub-agents for research** — the existing `mini-prophet` architecture
  decomposes into sub-agents per sub-question; a 24-hour-hackathon-feasible
  upgrade would replicate that here.
- **Multi-outcome Kelly** — current Kelly logic is binary-only; extend to
  multi-class markets like league champions.
