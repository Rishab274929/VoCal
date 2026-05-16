"""JSON extraction from messy LLM outputs."""

from __future__ import annotations

import pytest

from sigma_prophet.utils.json_utils import (
    extract_json_array,
    extract_json_object,
    strip_fences,
)


def test_strip_fences_json_block():
    text = "```json\n{\"a\": 1}\n```"
    assert strip_fences(text) == "{\"a\": 1}"


def test_strip_fences_no_fence_passes_through():
    assert strip_fences("hello") == "hello"


def test_extract_json_object_with_leading_prose():
    text = "Sure! Here is the answer:\n```json\n{\"x\": 1, \"y\": [1,2]}\n```"
    obj = extract_json_object(text)
    assert obj == {"x": 1, "y": [1, 2]}


def test_extract_json_object_with_trailing_comma():
    text = "{\"a\": 1, \"b\": 2,}"
    obj = extract_json_object(text)
    assert obj == {"a": 1, "b": 2}


def test_extract_json_object_missing_braces_raises():
    with pytest.raises(ValueError):
        extract_json_object("not json at all")


def test_extract_json_array():
    text = "Result: [1, 2, 3]"
    assert extract_json_array(text) == [1, 2, 3]


def test_extract_json_array_with_trailing_comma():
    assert extract_json_array("[1, 2,]") == [1, 2]
