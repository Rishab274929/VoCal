"""Provider routing + key resolution for the LLM client."""

from __future__ import annotations

import json

import httpx
import pytest

from sigma_prophet.prediction.llm_client import (
    LLMClient,
    LLMError,
    resolve_api_key,
    resolve_base_url,
)


def test_resolve_base_url_wafer():
    assert resolve_base_url("wafer") == "https://pass.wafer.ai/v1"


def test_resolve_base_url_openrouter():
    assert resolve_base_url("openrouter") == "https://openrouter.ai/api/v1"


def test_resolve_base_url_unknown_provider_raises():
    with pytest.raises(LLMError):
        resolve_base_url("notreal")


def test_resolve_base_url_custom_override():
    assert resolve_base_url("anything", base_url="https://x.test/v1") == "https://x.test/v1"


def test_resolve_api_key_uses_explicit(monkeypatch):
    monkeypatch.delenv("WAFER_API_KEY", raising=False)
    assert resolve_api_key("wafer", explicit="abc") == "abc"


def test_resolve_api_key_reads_env(monkeypatch):
    monkeypatch.setenv("WAFER_API_KEY", "wfr-xyz")
    assert resolve_api_key("wafer") == "wfr-xyz"


def test_resolve_api_key_missing_raises(monkeypatch):
    monkeypatch.delenv("WAFER_API_KEY", raising=False)
    with pytest.raises(LLMError):
        resolve_api_key("wafer")


def _stub_transport(response: dict, status: int = 200) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(status, json=response)
    return httpx.MockTransport(handler)


def test_chat_returns_content(monkeypatch):
    monkeypatch.setenv("WAFER_API_KEY", "wfr-test")
    client = LLMClient(provider="wafer")
    # Inject a mock transport into the cached httpx client.
    payload = {
        "choices": [
            {
                "message": {"role": "assistant", "content": "hello world", "reasoning_content": None},
                "finish_reason": "stop",
            }
        ],
        "usage": {"total_tokens": 10},
    }
    client._client_cache = httpx.Client(
        base_url="https://pass.wafer.ai/v1",
        transport=_stub_transport(payload),
        headers={"Authorization": "Bearer wfr-test"},
    )
    resp = client.chat(
        model="GLM-5.1",
        messages=[{"role": "user", "content": "hi"}],
        max_tokens=100,
    )
    assert resp.content == "hello world"
    assert resp.finish_reason == "stop"
    assert resp.usage == {"total_tokens": 10}


def test_chat_falls_back_to_reasoning_content_when_content_empty(monkeypatch):
    monkeypatch.setenv("WAFER_API_KEY", "wfr-test")
    client = LLMClient(provider="wafer")
    payload = {
        "choices": [
            {
                "message": {"role": "assistant", "content": None, "reasoning_content": "thinking out loud"},
                "finish_reason": "length",
            }
        ],
        "usage": {},
    }
    client._client_cache = httpx.Client(
        base_url="https://pass.wafer.ai/v1",
        transport=_stub_transport(payload),
        headers={"Authorization": "Bearer wfr-test"},
    )
    resp = client.chat(model="Qwen3.5-397B-A17B", messages=[{"role": "user", "content": "x"}])
    assert resp.content == "thinking out loud"
    assert resp.finish_reason == "length"


def test_chat_raises_on_4xx(monkeypatch):
    monkeypatch.setenv("WAFER_API_KEY", "wfr-test")
    client = LLMClient(provider="wafer")
    client._client_cache = httpx.Client(
        base_url="https://pass.wafer.ai/v1",
        transport=_stub_transport({"error": {"message": "bad"}}, status=400),
        headers={"Authorization": "Bearer wfr-test"},
    )
    with pytest.raises(LLMError) as exc:
        client.chat(model="GLM-5.1", messages=[{"role": "user", "content": "x"}])
    assert "400" in str(exc.value)
