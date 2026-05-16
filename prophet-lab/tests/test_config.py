"""Config loading from YAML + env."""

from __future__ import annotations

from pathlib import Path

import yaml

from sigma_prophet.config import load_config


def test_load_config_default_models_when_yaml_missing(tmp_path: Path, monkeypatch):
    monkeypatch.delenv("WAFER_API_KEY", raising=False)
    cfg = load_config(tmp_path / "missing.yaml")
    assert cfg.models, "default models should be populated"
    assert cfg.slug == "sigma-prophet"
    assert cfg.trading.kelly_fraction == 0.25
    # Default ensemble is Wafer-only.
    assert all(m.provider == "wafer" for m in cfg.models)


def test_load_config_reads_yaml_overrides(tmp_path: Path):
    path = tmp_path / "c.yaml"
    yaml.safe_dump(
        {
            "slug": "custom-slug",
            "n_ticks": 8,
            "models": [
                {
                    "name": "anthropic/claude-sonnet-4.5",
                    "provider": "openrouter",
                    "weight": 0.5,
                    "temperature": 0.1,
                }
            ],
            "trading": {"kelly_fraction": 0.5, "min_edge": 0.1},
            "calibration": {"shrink_to_prior": 0.2},
        },
        path.open("w"),
    )
    cfg = load_config(path)
    assert cfg.slug == "custom-slug"
    assert cfg.n_ticks == 8
    assert len(cfg.models) == 1
    assert cfg.models[0].name == "anthropic/claude-sonnet-4.5"
    assert cfg.models[0].provider == "openrouter"
    assert cfg.trading.kelly_fraction == 0.5
    assert cfg.trading.min_edge == 0.1
    assert cfg.calibration.shrink_to_prior == 0.2


def test_env_overrides_secrets(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("WAFER_API_KEY", "wfr-test")
    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-or-test")
    monkeypatch.setenv("PA_SERVER_API_KEY", "prophet-test")
    cfg = load_config(tmp_path / "missing.yaml")
    assert cfg.wafer_api_key == "wfr-test"
    assert cfg.openrouter_api_key == "sk-or-test"
    assert cfg.pa_server_api_key == "prophet-test"


def test_to_dict_omits_secrets(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("WAFER_API_KEY", "wfr-secret")
    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-or-secret")
    cfg = load_config(tmp_path / "missing.yaml")
    serialized = cfg.to_dict()
    assert "wafer_api_key" not in serialized
    assert "openrouter_api_key" not in serialized
    assert "pa_server_api_key" not in serialized
    # provider info IS exposed (non-secret)
    assert all("provider" in m for m in serialized["models"])
