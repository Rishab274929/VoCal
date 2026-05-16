#!/usr/bin/env bash
# Install the project in editable mode using the right Python (3.11+).
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$HERE"

PYTHON="${PYTHON:-python3}"
"$PYTHON" -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
echo ">> done. activate with: source .venv/bin/activate"
