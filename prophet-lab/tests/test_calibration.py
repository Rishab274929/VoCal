"""Calibration math: shrink, clip, smooth, Brier, log loss."""

from __future__ import annotations

import math

import pytest

from sigma_prophet.prediction.calibration import (
    apply_calibration,
    brier_score,
    clip_extremes,
    log_odds_smooth,
    log_score,
    normalize,
    shrink_to_prior,
)


def test_normalize_basic():
    out = normalize([1.0, 1.0, 2.0])
    assert pytest.approx(sum(out), abs=1e-9) == 1.0
    assert out[0] == pytest.approx(0.25)
    assert out[2] == pytest.approx(0.5)


def test_normalize_handles_zero():
    out = normalize([0.0, 0.0])
    assert pytest.approx(sum(out), abs=1e-9) == 1.0
    assert out[0] == out[1] == 0.5


def test_normalize_clamps_negatives():
    out = normalize([-1.0, 1.0])
    assert sum(out) == pytest.approx(1.0)
    assert out[0] == 0.0
    assert out[1] == 1.0


def test_clip_extremes_clamps_and_renorms():
    out = clip_extremes([0.01, 0.99], min_p=0.05, max_p=0.95)
    assert all(0.05 <= p <= 0.95 for p in out)
    assert sum(out) == pytest.approx(1.0)


def test_shrink_to_prior_uniform_default():
    out = shrink_to_prior([0.9, 0.1], weight=0.5)
    # halfway between original and (0.5, 0.5) → (0.7, 0.3)
    assert out[0] == pytest.approx(0.7, abs=1e-6)
    assert out[1] == pytest.approx(0.3, abs=1e-6)


def test_shrink_to_prior_custom():
    out = shrink_to_prior([0.9, 0.1], prior=[0.3, 0.7], weight=1.0)
    assert out == pytest.approx([0.3, 0.7])


def test_shrink_to_prior_weight_zero_is_identity():
    out = shrink_to_prior([0.4, 0.6], weight=0.0)
    assert out == pytest.approx([0.4, 0.6])


def test_log_odds_smooth_reduces_extremes():
    out = log_odds_smooth([0.99, 0.01], amount=0.5)
    # extremes should move toward 0.5
    assert out[0] < 0.99
    assert out[1] > 0.01
    assert sum(out) == pytest.approx(1.0)


def test_apply_calibration_full_pipeline():
    out = apply_calibration(
        [0.9999, 0.0001],
        shrink_to_prior_weight=0.1,
        min_prob=0.05,
        max_prob=0.95,
    )
    assert all(0.05 <= p <= 0.95 for p in out)
    assert sum(out) == pytest.approx(1.0, abs=1e-6)


def test_brier_score_perfect():
    assert brier_score([1.0, 0.0], [1, 0]) == 0.0


def test_brier_score_worst_binary():
    # Predicting 1.0 on the wrong outcome gives Brier 1.0 on each component
    assert brier_score([0.0, 1.0], [1, 0]) == pytest.approx(1.0)


def test_brier_score_mean_squared():
    # 0.7 for outcome 1, 0.3 for outcome 0 → ((0.7-1)^2 + (0.3-0)^2)/2 = 0.09
    assert brier_score([0.7, 0.3], [1, 0]) == pytest.approx(0.09)


def test_log_score_perfect_is_near_zero():
    assert log_score([1.0, 0.0], [1, 0]) == pytest.approx(0.0, abs=1e-3)


def test_log_score_increases_with_miscalibration():
    good = log_score([0.8, 0.2], [1, 0])
    bad = log_score([0.5, 0.5], [1, 0])
    assert bad > good
