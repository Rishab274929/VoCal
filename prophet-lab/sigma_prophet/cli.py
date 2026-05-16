"""SigmaProphet CLI.

Subcommands:
  forecast PATH        Batch-predict from events.json
  trade                Run the long-lived trade loop
  serve                Start FastAPI prediction endpoint
  eval PATH            Score the ensemble against a resolved dataset
  predict --title …    One-shot prediction from the shell
  show-config          Print the effective config (no secrets)
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import click

from sigma_prophet._version import __version__
from sigma_prophet.config import load_config
from sigma_prophet.logging_utils import setup_logging

logger = logging.getLogger(__name__)


def _load_dotenv_if_present() -> None:
    """Load a .env file from the current working directory if available."""
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv()
    here = Path(".env")
    if here.exists():
        load_dotenv(here)


@click.group()
@click.version_option(__version__, prog_name="prophet-lab")
@click.option("--config", "config_path", default=None, help="Path to config.yaml")
@click.option("-v", "--verbose", is_flag=True, help="Verbose logging")
@click.pass_context
def cli(ctx: click.Context, config_path: str | None, verbose: bool) -> None:
    """SigmaProphet — Prophet Arena forecasting & trading agent."""
    _load_dotenv_if_present()
    cfg = load_config(config_path)
    if verbose:
        cfg.log_level = "DEBUG"
    setup_logging(cfg.log_level)
    ctx.obj = cfg


@cli.command()
@click.pass_obj
def show_config(cfg) -> None:
    """Print the effective configuration."""
    click.echo(json.dumps(cfg.to_dict(), indent=2))


@cli.command()
@click.option("--events", "events_path", required=True, help="Path to events.json")
@click.option("--output", "-o", "output_path", default=None, help="Where to write predictions.json")
@click.pass_obj
def forecast(cfg, events_path: str, output_path: str | None) -> None:
    """Batch-predict for the forecast track."""
    from sigma_prophet.arena.forecast_client import ForecastTrackRunner

    runner = ForecastTrackRunner(cfg)
    output_path = output_path or cfg.forecast.output_path
    summary = runner.run(events_path, output_path)
    click.echo(json.dumps(summary, indent=2))


@cli.command("predict")
@click.option("--title", required=True, help="Question to forecast")
@click.option("--outcomes", default="Yes,No", help="Comma-separated outcome labels")
@click.option("--rules", default=None, help="Resolution rules text")
@click.option("--close-time", "close_time", default=None, help="Close time ISO string")
@click.option("--no-research", is_flag=True, help="Skip web research")
@click.pass_obj
def predict_one(cfg, title: str, outcomes: str, rules: str | None, close_time: str | None, no_research: bool) -> None:
    """Run a single prediction from the command line."""
    from sigma_prophet.arena.forecast_client import _build_forecaster, _build_research, _predict_with_components

    if no_research:
        cfg.research.enabled = False
    forecaster = _build_forecaster(cfg)
    research = _build_research(cfg)
    event = {
        "title": title,
        "outcomes": [o.strip() for o in outcomes.split(",") if o.strip()],
        "rules": rules,
        "close_time": close_time,
        "category": "general",
    }
    result = _predict_with_components(event, forecaster, research)
    click.echo(json.dumps(result, indent=2))


@cli.command()
@click.option("--max-ticks", "max_ticks", type=int, default=None, help="Stop after N ticks")
@click.option("--slug", default=None, help="Override experiment slug")
@click.option("--model-label", "model_label", default="sigma:prophet-ensemble")
@click.pass_obj
def trade(cfg, max_ticks: int | None, slug: str | None, model_label: str) -> None:
    """Run the trade-track tick loop."""
    if slug:
        cfg.slug = slug
    from sigma_prophet.arena.trade_client import TradeTrackRunner

    runner = TradeTrackRunner(cfg)
    runner.run(max_ticks=max_ticks, model_label=model_label)


@cli.command()
@click.option("--port", default=8000, type=int)
@click.option("--host", default="0.0.0.0")
@click.pass_obj
def serve(cfg, port: int, host: str) -> None:
    """Serve the FastAPI prediction endpoint."""
    import uvicorn

    from sigma_prophet.arena.server import get_app

    logger.info("starting uvicorn on %s:%d", host, port)
    uvicorn.run(get_app(), host=host, port=port)


@cli.command("eval")
@click.option("--events", "events_path", required=True, help="Path to resolved events JSON")
@click.option("--limit", type=int, default=None, help="Only score the first N events")
@click.option("--with-research", is_flag=True, help="Enable web research during eval")
@click.option("--output", "-o", "output_path", default="outputs/eval_report.json")
@click.pass_obj
def eval_cmd(cfg, events_path: str, limit: int | None, with_research: bool, output_path: str) -> None:
    """Score the ensemble against a resolved dataset."""
    from sigma_prophet.offline.evaluator import OfflineEvaluator

    evaluator = OfflineEvaluator(cfg=cfg)
    report = evaluator.evaluate(
        events_path,
        limit=limit,
        with_research=with_research,
        output_path=output_path,
    )
    summary = {
        "n_events": report.n_events,
        "n_scored": report.n_scored,
        "mean_brier": round(report.mean_brier, 4),
        "mean_logloss": round(report.mean_logloss, 4),
    }
    click.echo(json.dumps(summary, indent=2))


def main(argv: list[str] | None = None) -> None:
    try:
        cli.main(args=argv, standalone_mode=False)
    except click.exceptions.Abort:
        sys.exit(130)
    except click.exceptions.UsageError as exc:
        click.echo(str(exc), err=True)
        sys.exit(2)


if __name__ == "__main__":
    main()
