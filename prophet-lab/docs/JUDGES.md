# Judge run instructions

This document is everything you need to evaluate Prophet Lab in a standardized
environment.

## Prerequisites

- Python ≥ 3.11
- `WAFER_API_KEY` exported (or in `.env`) — backs the default GLM-5.1 + Qwen3.5 ensemble
- (Optional) `OPENROUTER_API_KEY` to add Claude/GPT/Gemini/Llama heads to the ensemble
- (Optional) `BRAVE_API_KEY` or `TAVILY_API_KEY` for web research
- (Trade track only) `PA_SERVER_API_KEY` for prophetarena.co

## One-line setup

```bash
cd prophet-lab
cp .env.example .env       # fill in ANTHROPIC_API_KEY
./run.sh smoke             # builds venv, runs unit tests, prints effective config
```

The first invocation of `./run.sh` creates `.venv/` and installs all
dependencies; subsequent runs are instant.

## Track 1 — Forecast

Predict probabilities for a set of events:

```bash
# pull a fresh slate from the Prophet Arena sample registry
prophet forecast retrieve --dataset sample-sports -o events.json

# batch-predict with SigmaProphet
./run.sh forecast events.json outputs/predictions.json

# OR submit via the standard CLI hook
prophet forecast predict \
    --events events.json \
    --local sigma_prophet.arena.forecast_client
```

To score the predictions locally:

```bash
prophet forecast retrieve --dataset sample-resolved --include-resolved -o resolved.json
./run.sh eval resolved.json --limit 10
# → prints { "mean_brier": 0.18xx, "mean_logloss": ..., "n_scored": ... }
```

## Track 2 — Trade

Run the long-lived 15-min tick loop:

```bash
./run.sh trade --slug sigma-prophet-judges --max-ticks 4
```

Each tick:
1. Claims a tick from the arena
2. Pulls the candidate markets + portfolio
3. For each market, the ensemble forecasts a calibrated p_yes (optionally with web research)
4. Kelly strategy sizes a trade if edge > config.trading.min_edge
5. Submits intents, finalizes, advances

You can watch live PnL with the official dashboard:

```bash
prophet trade dashboard --slug sigma-prophet-judges
```

## Track 3 — Hosted endpoint

For the onboarding flow that calls a remote endpoint:

```bash
./run.sh serve --port 8000
# → POST http://localhost:8000/predict           (Prophet Arena native shape)
# → POST http://localhost:8000/chat/completions  (OpenAI-compatible shape)
```

Set `SIGMA_BEARER_TOKEN=xyz` in `.env` to require `Authorization: Bearer xyz`
on `/chat/completions`. Leave unset for the local-test path.

## Reproducibility

- Random number usage is limited to retry jitter (logged) — predictions are
  Claude-temperature-driven but the calibration pipeline is deterministic.
- The full `config.yaml` is logged at startup; `./run.sh show-config` prints
  the effective configuration including any environment-driven overrides.
- The `config_hash` written into each Prophet Arena experiment is the
  SHA-256 of the serialized config — resuming a crashed run with the same
  config picks up where it left off.

## Verifying correctness without API keys

```bash
./run.sh pytest -q                # unit tests for calibration / strategy / parsing
```

These tests do NOT hit Claude or the arena — they verify the math and the
JSON parsing on canned inputs. The output should be:

```
======== N passed in 0.xxs ========
```

## Troubleshooting

| Symptom                                        | Fix                                                                                       |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `ANTHROPIC_API_KEY not set`                    | `cp .env.example .env` and fill in the key                                                |
| `BraveSearch / TavilySearch ... skipping`      | Expected if you didn't set the key. Research disables itself gracefully.                  |
| `experiment_completed` immediately on `trade`  | The slug already finished its `n_ticks`. Use a new `--slug` or raise `n_ticks` in YAML.   |
| `submission deadline exceeded` (HTTP 409)      | You're past the 9-min submit window. The next tick will pick up automatically.            |
| Slow ensemble                                  | Disable research (`--no-research`) or trim `models:` in `config.yaml`.                    |

## Contact

Eric Spencer · ericspencer1450@gmail.com · UncommonHacks 2026
