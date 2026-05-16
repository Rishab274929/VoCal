#!/usr/bin/env bash
# Offline smoke test: no API calls, just verifies the math and imports.
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$HERE"

if [[ -d .venv ]]; then
    source .venv/bin/activate
fi

python -m pytest tests -q
