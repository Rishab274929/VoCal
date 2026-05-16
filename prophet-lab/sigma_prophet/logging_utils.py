"""Structured logging for SigmaProphet."""

from __future__ import annotations

import json
import logging
import sys
import time
from typing import Any


class _ColorFormatter(logging.Formatter):
    """Lightweight colored console formatter."""

    COLORS = {
        "DEBUG": "\033[36m",
        "INFO": "\033[32m",
        "WARNING": "\033[33m",
        "ERROR": "\033[31m",
        "CRITICAL": "\033[35m",
    }
    RESET = "\033[0m"

    def format(self, record: logging.LogRecord) -> str:
        color = self.COLORS.get(record.levelname, "")
        ts = time.strftime("%H:%M:%S", time.localtime(record.created))
        name = record.name.replace("sigma_prophet.", "sp.")
        msg = record.getMessage()
        return f"{color}{ts} {record.levelname:<7}{self.RESET} {name:<28} {msg}"


def setup_logging(level: str = "INFO") -> None:
    """Configure root logger with a single colored stream handler."""
    root = logging.getLogger()
    root.setLevel(level.upper())
    for h in list(root.handlers):
        root.removeHandler(h)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_ColorFormatter())
    root.addHandler(handler)

    # quiet down chatty libraries
    for noisy in ("httpx", "httpcore", "anthropic", "urllib3"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def jdump(payload: Any) -> str:
    """Compact JSON for log lines."""
    try:
        return json.dumps(payload, separators=(",", ":"), default=str)
    except (TypeError, ValueError):
        return repr(payload)
