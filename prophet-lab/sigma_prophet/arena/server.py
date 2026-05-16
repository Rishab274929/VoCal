"""Hosted prediction endpoint.

Prophet Arena's onboarding flow expects either:

  - A POST endpoint at ``/predict`` returning a probabilities array.
  - An OpenAI-compatible ``/chat/completions`` endpoint whose assistant
    text contains a JSON object with the same shape.

This server exposes both so judges can register a single URL.

Run:

    python -m sigma_prophet.arena.server               # default port 8000
    uvicorn sigma_prophet.arena.server:app             # via uvicorn
"""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Any

from sigma_prophet.arena.forecast_client import _build_forecaster, _build_research, predict_event
from sigma_prophet.config import load_config
from sigma_prophet.logging_utils import setup_logging
from sigma_prophet.prediction.ensemble import EnsembleForecaster
from sigma_prophet.research.evidence import ResearchAgent

logger = logging.getLogger(__name__)

_LAZY: dict[str, Any] = {"cfg": None, "forecaster": None, "research": None}


def _ensure_components() -> tuple[Any, EnsembleForecaster, ResearchAgent | None]:
    if _LAZY["cfg"] is None:
        _LAZY["cfg"] = load_config()
        _LAZY["forecaster"] = _build_forecaster(_LAZY["cfg"])
        _LAZY["research"] = _build_research(_LAZY["cfg"])
    return _LAZY["cfg"], _LAZY["forecaster"], _LAZY["research"]


def build_app():  # noqa: C901 - keeps fastapi optional
    from fastapi import Body, FastAPI, HTTPException, Depends
    from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
    from pydantic import BaseModel

    setup_logging()

    class EventRequest(BaseModel):
        title: str | None = None
        question: str | None = None
        event_ticker: str | None = None
        market_ticker: str | None = None
        subtitle: str | None = None
        description: str | None = None
        category: str | None = "general"
        rules: str | None = None
        close_time: str | None = None
        outcomes: list[str] | None = None

    class MarketProbability(BaseModel):
        market: str
        probability: float

    class PredictionResponse(BaseModel):
        probabilities: list[MarketProbability]
        rationale: str = ""

    class ChatMessage(BaseModel):
        role: str
        content: str

    class ChatCompletionRequest(BaseModel):
        model: str = "sigma-prophet"
        messages: list[ChatMessage]
        max_tokens: int | None = 1500
        temperature: float | None = 0.2
        stream: bool | None = False

    app = FastAPI(title="SigmaProphet Forecasting Agent")
    security = HTTPBearer(auto_error=False)

    @app.get("/health")
    def health() -> dict[str, Any]:
        cfg, _, _ = _ensure_components()
        return {
            "status": "ok",
            "service": "sigma-prophet",
            "models": [m.name for m in cfg.models],
            "research_enabled": cfg.research.enabled,
        }

    @app.post("/predict", response_model=PredictionResponse)
    def predict_route(event: EventRequest) -> PredictionResponse:
        cfg, forecaster, research = _ensure_components()
        ev = event.model_dump()
        if not ev.get("title"):
            ev["title"] = ev.get("question") or ev.get("market_ticker") or "Untitled"
        ev["outcomes"] = ev.get("outcomes") or ["Yes", "No"]
        from sigma_prophet.arena.forecast_client import _predict_with_components

        try:
            out = _predict_with_components(ev, forecaster, research)
        except Exception as exc:
            logger.exception("predict failed: %s", exc)
            raise HTTPException(status_code=500, detail=str(exc)) from exc
        return PredictionResponse(
            probabilities=[
                MarketProbability(market=p["market"], probability=p["probability"])
                for p in out["probabilities"]
            ],
            rationale=out.get("rationale", ""),
        )

    @app.post("/chat/completions")
    def chat_completions(
        request: ChatCompletionRequest,
        credentials: HTTPAuthorizationCredentials | None = Depends(security),
    ) -> dict[str, Any]:
        """OpenAI-compatible adapter so Prophet Arena's onboarding can call us.

        The user message is expected to contain enough info (title +
        outcomes) for the forecaster. We parse a best-effort event dict
        from it, run the ensemble, and return the prediction JSON as the
        assistant content.
        """
        expected = os.environ.get("SIGMA_BEARER_TOKEN")
        if expected and (credentials is None or credentials.credentials != expected):
            raise HTTPException(status_code=401, detail="invalid bearer token")

        if not request.messages:
            raise HTTPException(status_code=400, detail="no messages")
        last_user = next(
            (m.content for m in reversed(request.messages) if m.role == "user"),
            request.messages[-1].content,
        )
        event = _coerce_event_from_text(last_user)
        try:
            result = predict_event(event)
        except Exception as exc:
            logger.exception("chat_completions predict failed: %s", exc)
            raise HTTPException(status_code=500, detail=str(exc)) from exc

        content = json.dumps(
            {
                "probabilities": {
                    p["market"]: p["probability"] for p in result["probabilities"]
                },
                "rationale": result.get("rationale", ""),
            },
            indent=2,
        )
        return {
            "id": f"chatcmpl-sigma-{int(time.time())}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": request.model,
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": content},
                    "finish_reason": "stop",
                }
            ],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        }

    return app


_APP: Any | None = None


def get_app():
    """Lazy-construct the FastAPI app on first access."""
    global _APP
    if _APP is None:
        _APP = build_app()
    return _APP


def __getattr__(name: str):  # type: ignore[misc]
    """Module-level ``app`` resolves lazily so import doesn't need fastapi."""
    if name == "app":
        return get_app()
    raise AttributeError(name)


def _coerce_event_from_text(text: str) -> dict[str, Any]:
    """Try to parse a JSON event from the user message; fall back to title-only."""
    text = text.strip()
    # JSON block first
    try:
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            candidate = json.loads(text[start : end + 1])
            if isinstance(candidate, dict) and ("title" in candidate or "question" in candidate):
                return candidate
    except json.JSONDecodeError:
        pass
    # Outcomes heuristics
    return {
        "title": text[:500],
        "outcomes": ["Yes", "No"],
        "category": "general",
    }


def main() -> None:
    import uvicorn

    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run(get_app(), host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
