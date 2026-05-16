"""Robust JSON parsing from LLM outputs.

LLMs frequently wrap JSON in markdown fences, add chatty prefixes, or
emit a trailing comma. These helpers extract a clean object/array.
"""

from __future__ import annotations

import json
import re
from typing import Any

_FENCE_RE = re.compile(r"^```(?:json)?\s*", re.IGNORECASE)


def strip_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = _FENCE_RE.sub("", text)
    if text.endswith("```"):
        text = text.rsplit("```", 1)[0]
    return text.strip()


def extract_json_object(text: str) -> dict[str, Any]:
    """Pull the first {...} object out of a model response."""
    text = strip_fences(text)
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise ValueError(f"No JSON object found in: {text[:200]!r}")
    snippet = text[start : end + 1]
    try:
        return json.loads(snippet)
    except json.JSONDecodeError:
        cleaned = re.sub(r",\s*([}\]])", r"\1", snippet)
        return json.loads(cleaned)


def extract_json_array(text: str) -> list[Any]:
    """Pull the first [...] array out of a model response."""
    text = strip_fences(text)
    start = text.find("[")
    end = text.rfind("]")
    if start == -1 or end == -1 or end < start:
        raise ValueError(f"No JSON array found in: {text[:200]!r}")
    snippet = text[start : end + 1]
    try:
        return json.loads(snippet)
    except json.JSONDecodeError:
        cleaned = re.sub(r",\s*([}\]])", r"\1", snippet)
        return json.loads(cleaned)
