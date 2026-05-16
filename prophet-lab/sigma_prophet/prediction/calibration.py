"""Calibration utilities.

Reduces miscalibration two ways:
  - Shrinkage toward a prior (uniform, or market-implied).
  - Clamping extreme probabilities away from 0/1.

Also exposes scoring functions used by the offline evaluator.
"""

from __future__ import annotations

import math
from collections.abc import Sequence


def _uniform(n: int) -> list[float]:
    if n <= 0:
        return []
    return [1.0 / n] * n


def normalize(probs: Sequence[float]) -> list[float]:
    """Project onto the simplex (non-negative, sum to 1)."""
    cleaned = [max(0.0, float(p)) for p in probs]
    s = sum(cleaned)
    if s <= 0:
        return _uniform(len(cleaned))
    return [p / s for p in cleaned]


def clip_extremes(probs: Sequence[float], *, min_p: float = 0.02, max_p: float = 0.98) -> list[float]:
    """Clamp each component into [min_p, max_p], then renormalize."""
    clamped = [min(max(p, min_p), max_p) for p in probs]
    return normalize(clamped)


def shrink_to_prior(
    probs: Sequence[float],
    *,
    prior: Sequence[float] | None = None,
    weight: float = 0.1,
) -> list[float]:
    """Convex combination toward ``prior`` (uniform when prior is None).

    ``weight`` is the share of mass moved to the prior — 0 returns ``probs``
    unchanged, 1 returns the prior.
    """
    weight = max(0.0, min(1.0, float(weight)))
    if not probs:
        return []
    if prior is None:
        prior = _uniform(len(probs))
    if len(prior) != len(probs):
        raise ValueError("prior length mismatch")
    mixed = [(1 - weight) * p + weight * q for p, q in zip(probs, prior, strict=True)]
    return normalize(mixed)


def log_odds_smooth(probs: Sequence[float], amount: float = 0.1) -> list[float]:
    """Soften the distribution by pulling log-odds toward zero.

    For each component, compute log(p / (1-p)), multiply by (1 - amount),
    map back. Useful for reducing extreme confidence without flattening to
    uniform.
    """
    amount = max(0.0, min(1.0, float(amount)))
    if amount == 0.0 or not probs:
        return list(probs)
    smoothed = []
    for p in probs:
        p = min(max(p, 1e-6), 1 - 1e-6)
        logit = math.log(p / (1 - p)) * (1 - amount)
        smoothed.append(1.0 / (1.0 + math.exp(-logit)))
    return normalize(smoothed)


def apply_calibration(
    probs: Sequence[float],
    *,
    prior: Sequence[float] | None = None,
    shrink_to_prior_weight: float = 0.1,
    min_prob: float = 0.02,
    max_prob: float = 0.98,
    log_odds_smoothing: float = 0.0,
) -> list[float]:
    """Run the full calibration pipeline."""
    out = normalize(probs)
    if shrink_to_prior_weight > 0:
        out = shrink_to_prior(out, prior=prior, weight=shrink_to_prior_weight)
    if log_odds_smoothing > 0:
        out = log_odds_smooth(out, log_odds_smoothing)
    out = clip_extremes(out, min_p=min_prob, max_p=max_prob)
    return out


def brier_score(probs: Sequence[float], outcomes: Sequence[int]) -> float:
    """Multi-class Brier score. ``outcomes`` is one-hot over the same indices.

    Returns mean squared error across components (0 = perfect, 1 = worst-case
    for a degenerate guess on a binary).
    """
    if len(probs) != len(outcomes):
        raise ValueError("probs/outcomes length mismatch")
    if not probs:
        return 0.0
    return sum((p - o) ** 2 for p, o in zip(probs, outcomes, strict=True)) / len(probs)


def log_score(probs: Sequence[float], outcomes: Sequence[int], *, eps: float = 1e-6) -> float:
    """Log loss / negative log likelihood. Lower is better."""
    if len(probs) != len(outcomes):
        raise ValueError("probs/outcomes length mismatch")
    loss = 0.0
    for p, o in zip(probs, outcomes, strict=True):
        p = min(max(p, eps), 1 - eps)
        loss += -(o * math.log(p) + (1 - o) * math.log(1 - p))
    return loss / len(probs) if probs else 0.0
