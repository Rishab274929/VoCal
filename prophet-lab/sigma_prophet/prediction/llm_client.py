"""Provider-routed LLM client.

Talks to OpenAI-compatible /v1/chat/completions endpoints.

Supported providers:
  - ``wafer``      → https://pass.wafer.ai/v1  (key: WAFER_API_KEY)
  - ``openrouter`` → https://openrouter.ai/api/v1 (key: OPENROUTER_API_KEY)
  - ``openai``     → https://api.openai.com/v1 (key: OPENAI_API_KEY)
  - ``custom``     → caller-supplied base_url + env var name

Some Wafer models (Qwen3.5) are reasoning-style: they emit text in
``reasoning_content`` and leave ``content`` empty when their token budget
is exhausted before the final answer. The client falls back to
``reasoning_content`` when ``content`` is empty so downstream JSON
extraction has something to work with.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)

# Default endpoints per provider.
PROVIDER_BASE_URLS: dict[str, str] = {
    "wafer": "https://pass.wafer.ai/v1",
    "openrouter": "https://openrouter.ai/api/v1",
    "openai": "https://api.openai.com/v1",
}

# Env var per provider.
PROVIDER_KEY_ENVS: dict[str, str] = {
    "wafer": "WAFER_API_KEY",
    "openrouter": "OPENROUTER_API_KEY",
    "openai": "OPENAI_API_KEY",
}

# Models we ship with — provider name → canonical model id.
# Wafer model names are case-insensitive per their docs but we use the
# canonical capitalization to match curl examples in the wild.
KNOWN_WAFER_MODELS = {
    "GLM-5.1",
    "Qwen3.5-397B-A17B",
    "Qwen3.6-35B-A3B",
    "qwen3.6-max-preview",
    "DeepSeek-V4-Pro",
    "MiniMax-M2.7",
}


class LLMError(Exception):
    """Wrapping HTTP/transport errors so callers can catch one type."""


@dataclass
class ChatResponse:
    content: str
    model: str
    finish_reason: str | None
    usage: dict[str, int]
    raw: dict


def resolve_base_url(provider: str, base_url: str | None = None) -> str:
    if base_url:
        return base_url.rstrip("/")
    key = provider.lower().strip()
    if key not in PROVIDER_BASE_URLS:
        raise LLMError(f"Unknown provider {provider!r}; pass base_url explicitly.")
    return PROVIDER_BASE_URLS[key]


def resolve_api_key(provider: str, explicit: str | None = None) -> str:
    if explicit:
        return explicit
    key = provider.lower().strip()
    env = PROVIDER_KEY_ENVS.get(key)
    if env is None:
        raise LLMError(f"No env-var mapping for provider {provider!r}; pass api_key explicitly.")
    val = os.environ.get(env, "").strip()
    if not val:
        raise LLMError(
            f"Missing {env} for provider {provider!r}. Add it to .env or your shell."
        )
    return val


class LLMClient:
    """Thin wrapper around POST /v1/chat/completions."""

    def __init__(
        self,
        provider: str = "wafer",
        *,
        api_key: str | None = None,
        base_url: str | None = None,
        timeout: int = 120,
        extra_headers: dict[str, str] | None = None,
    ):
        self.provider = provider.lower().strip()
        self.base_url = resolve_base_url(self.provider, base_url)
        self._api_key_explicit = api_key
        self.timeout = timeout
        self.extra_headers = extra_headers or {}
        self._client_cache: httpx.Client | None = None

    def _build_headers(self, api_key: str) -> dict[str, str]:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        if self.provider == "openrouter":
            # OpenRouter prefers an X-Title header for attribution
            headers.setdefault("HTTP-Referer", "https://github.com/EricSpencer00/uncommonhacks26")
            headers.setdefault("X-Title", "SigmaProphet")
        headers.update(self.extra_headers)
        return headers

    def _http(self, api_key: str) -> httpx.Client:
        if self._client_cache is None:
            self._client_cache = httpx.Client(
                base_url=self.base_url,
                timeout=self.timeout,
                headers=self._build_headers(api_key),
            )
        return self._client_cache

    def close(self) -> None:
        if self._client_cache is not None:
            self._client_cache.close()
            self._client_cache = None

    def chat(
        self,
        model: str,
        messages: list[dict[str, str]],
        *,
        max_tokens: int = 2000,
        temperature: float = 0.2,
        extra_body: dict | None = None,
    ) -> ChatResponse:
        api_key = resolve_api_key(self.provider, self._api_key_explicit)
        body: dict = {
            "model": model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        if extra_body:
            body.update(extra_body)

        client = self._http(api_key)
        try:
            response = client.post("/chat/completions", json=body)
        except httpx.HTTPError as exc:
            raise LLMError(f"transport error talking to {self.provider}: {exc}") from exc

        if response.status_code >= 400:
            raise LLMError(
                f"{self.provider} {model} returned {response.status_code}: {response.text[:400]}"
            )

        data = response.json()
        try:
            choice = data["choices"][0]
            message = choice["message"]
        except (KeyError, IndexError, TypeError) as exc:
            raise LLMError(f"malformed response from {self.provider}: {data!r}") from exc

        content = message.get("content")
        reasoning = message.get("reasoning_content")
        # Some Wafer reasoning models leave content empty when they run out of
        # budget before emitting the final answer. Fall back to reasoning text
        # so downstream JSON extraction can still try.
        if not content and reasoning:
            content = reasoning
        if content is None:
            content = ""

        return ChatResponse(
            content=str(content),
            model=model,
            finish_reason=choice.get("finish_reason"),
            usage=data.get("usage", {}) or {},
            raw=data,
        )

    def __enter__(self) -> "LLMClient":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:  # type: ignore[no-untyped-def]
        self.close()
