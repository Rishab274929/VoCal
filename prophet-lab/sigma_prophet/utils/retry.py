"""Retry with exponential backoff."""

from __future__ import annotations

import logging
import random
import time
from collections.abc import Callable
from typing import TypeVar

T = TypeVar("T")

logger = logging.getLogger(__name__)


def with_retries(
    fn: Callable[[], T],
    *,
    max_attempts: int = 3,
    initial_delay: float = 1.0,
    multiplier: float = 2.0,
    jitter: float = 0.5,
    label: str = "call",
    retry_on: tuple[type[BaseException], ...] = (Exception,),
) -> T:
    """Call ``fn`` up to ``max_attempts`` times, backing off between failures."""
    last_exc: BaseException | None = None
    delay = initial_delay
    for attempt in range(1, max_attempts + 1):
        try:
            return fn()
        except retry_on as exc:
            last_exc = exc
            if attempt == max_attempts:
                break
            sleep_for = delay + random.uniform(0, jitter)
            logger.warning(
                "%s failed (attempt %d/%d): %s — retrying in %.2fs",
                label,
                attempt,
                max_attempts,
                exc,
                sleep_for,
            )
            time.sleep(sleep_for)
            delay *= multiplier
    assert last_exc is not None
    raise last_exc
