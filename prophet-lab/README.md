# Prophet Lab — SigmaProphet

**AI Forecasting Agent for the Sigma Lab Track @ UncommonHacks 2026 (UChicago)**

Prophet Lab is a production-quality forecasting and trading agent built on top
of the [`ai-prophet-core`](https://pypi.org/project/ai-prophet-core/) SDK.
It competes on [prophetarena.co](https://prophetarena.co) — Sigma Lab's live
benchmark for LLM-driven prediction-market forecasting — and supports **both
tracks**:

| Track       | What it does                                            | Entry point                            |
| ----------- | ------------------------------------------------------- | -------------------------------------- |
| `forecast`  | Submits calibrated probability distributions per event  | `./run.sh forecast events.json`        |
| `trade`     | Long-lived 15-min tick loop, Kelly-sized prediction bets | `./run.sh trade`                       |
| `serve`     | Hosted `/predict` + OpenAI-compatible `/chat/completions` | `./run.sh serve`                       |
| `eval`      | Offline Brier scoring against resolved samples          | `./run.sh eval resolved.json`          |

## Highlights

- **Multi-provider LLM ensemble** — heterogeneous heads on **Wafer** (GLM-5.1,
  Qwen3.5-397B-A17B, DeepSeek-V4-Pro, MiniMax-M2.7) and **OpenRouter**
  (Claude, GPT, Gemini, Llama, …). Each `ModelSpec` carries its own
  provider; the client resolves the right endpoint and key automatically.
- **Two-stage research pipeline** — LLM decomposes the question into search queries,
  Brave / Tavily fetches evidence, then a reconciliation prompt produces the
  final distribution.
- **Brier-aware calibration** — shrinkage toward a prior, log-odds smoothing,
  extreme-probability clamping. The calibration block is fully unit-tested.
- **Kelly-criterion sizing** — fractional Kelly with market-implied shrinkage,
  per-market and per-tick risk caps that mirror Prophet Arena's server-side ruleset.
- **Reasoning-model aware** — Wafer's Qwen3.5 is a heavy reasoning model that
  emits text in `reasoning_content`; the client falls back to that field when
  `content` is empty so the JSON parser still gets something to work with.
- **Drop-in to the official CLI** — works as `prophet forecast predict --local
  sigma_prophet.arena.forecast_client`.
- **Hosted endpoint mode** — single FastAPI server speaks both Prophet Arena's
  native `/predict` shape and an OpenAI-compatible `/chat/completions`, so
  onboarding works either way.
- **Offline evaluator** — score the ensemble locally on `sample-resolved`
  without ever hitting the live arena.

## Quick start

```bash
cp .env.example .env
# fill in WAFER_API_KEY (required for the default ensemble)
# optional: OPENROUTER_API_KEY, BRAVE_API_KEY, TAVILY_API_KEY

# install + run a one-shot prediction
./run.sh predict "Will the Bears win Super Bowl LX?" "Yes,No"

# host the prediction endpoint
./run.sh serve
# → POST http://localhost:8000/predict  {"title": "...", "outcomes": [...]}

# forecast-track batch run (from a Prophet Arena events.json)
./run.sh forecast events.json outputs/predictions.json

# offline scoring against the resolved sample
prophet forecast retrieve --dataset sample-resolved --include-resolved -o resolved.json
./run.sh eval resolved.json
```

For the trade track you also need `PA_SERVER_API_KEY` set:

```bash
./run.sh trade --max-ticks 4 --slug sigma-prophet-test
```

## Architecture

```
events / market quotes
        │
        ▼
┌──────────────────┐    ┌──────────────────┐
│  ResearchAgent   │───▶│  EnsembleForecaster
│  decompose+search│    │  Opus + Sonnet + Haiku
└──────────────────┘    └──────┬───────────┘
                               │
                               ▼
                       ┌──────────────────┐
                       │ Calibration      │
                       │ shrink + clip    │
                       └──────┬───────────┘
                              │
              ┌───────────────┴────────────────┐
              ▼                                ▼
   ┌──────────────────┐              ┌──────────────────┐
   │ Forecast track   │              │  Trade track     │
   │  → probabilities │              │  Kelly sizing    │
   └──────────────────┘              │  risk budget     │
                                     │  tick lifecycle  │
                                     └──────────────────┘
```

See `docs/ARCHITECTURE.md` and `docs/METHODOLOGY.md` for the full design.

## Project layout

```
prophet-lab/
├── README.md
├── pyproject.toml
├── requirements.txt
├── run.sh                     ← judge entry point
├── config.yaml                ← runtime tunables
├── .env.example
├── sigma_prophet/             ← package
│   ├── agent.py               ← high-level facade
│   ├── cli.py                 ← Click CLI
│   ├── config.py              ← config loader
│   ├── arena/
│   │   ├── forecast_client.py ← forecast track + ``prophet forecast predict --local``
│   │   ├── trade_client.py    ← trade track orchestrator
│   │   └── server.py          ← FastAPI hosted endpoint
│   ├── prediction/
│   │   ├── forecaster.py      ← ClaudeForecaster
│   │   ├── ensemble.py        ← weighted ensemble + calibration
│   │   ├── calibration.py     ← shrink/clip + Brier/log-loss
│   │   └── prompts.py
│   ├── research/
│   │   ├── web_search.py      ← Brave / Tavily backends
│   │   └── evidence.py        ← decompose+search agent
│   ├── trading/
│   │   ├── strategy.py        ← Kelly sizing
│   │   ├── risk.py            ← per-tick risk state
│   │   └── executor.py        ← tick loop
│   ├── offline/evaluator.py   ← offline Brier scoring
│   └── utils/                 ← retry + JSON parsing helpers
├── tests/
└── docs/
    ├── ARCHITECTURE.md
    ├── METHODOLOGY.md
    └── JUDGES.md
```

## Configuration

Everything is configured via `config.yaml` (non-secret tunables) and `.env`
(secrets). The most important knobs:

```yaml
models:
  - name: GLM-5.1              # Wafer workhorse
    provider: wafer
    weight: 2.0
  - name: Qwen3.5-397B-A17B    # reasoning model — bigger budget
    provider: wafer
    weight: 1.0
    max_tokens: 4000
  # add OpenRouter heads for ensemble diversity:
  # - name: anthropic/claude-sonnet-4.5
  #   provider: openrouter
  #   weight: 1.5

trading:
  kelly_fraction: 0.25      # quarter-Kelly is the default
  min_edge: 0.05            # only trade when p - price > 5pp
  market_prior_weight: 0.35 # shrink toward market-mid this much

calibration:
  shrink_to_prior: 0.10     # 10% pull toward uniform
  min_prob: 0.02
  max_prob: 0.98
```

## License

MIT.

## Credits

Built for the Sigma Lab AI Forecasting Track at UncommonHacks 2026, UChicago.
SDK is © the AI Prophet team.
