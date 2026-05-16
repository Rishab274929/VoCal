#!/usr/bin/env bash
# SigmaProphet — single entry point for judges.
#
# Usage:
#   ./run.sh                              # default: serve hosted endpoint on :8000
#   ./run.sh serve                        # explicit
#   ./run.sh forecast events.json out.json
#   ./run.sh trade --max-ticks 4
#   ./run.sh eval resolved.json
#   ./run.sh predict "Will the Bears make the playoffs?" "Yes,No"
#   ./run.sh smoke                        # offline smoke test (no API calls)
#
# The script auto-creates a venv at .venv on first run and installs deps.

set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$HERE"

PYTHON="${PYTHON:-python3}"
VENV_DIR="${VENV_DIR:-$HERE/.venv}"

if [[ ! -d "$VENV_DIR" ]]; then
    echo ">> creating venv at $VENV_DIR"
    "$PYTHON" -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

if [[ ! -f "$VENV_DIR/.installed" || "${FORCE_REINSTALL:-0}" == "1" ]]; then
    echo ">> installing requirements"
    python -m pip install --upgrade pip >/dev/null
    python -m pip install -r requirements.txt
    touch "$VENV_DIR/.installed"
fi

if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

CMD="${1:-serve}"
shift || true

case "$CMD" in
    serve)
        exec python -m sigma_prophet serve "$@"
        ;;
    forecast)
        EVENTS="${1:?usage: ./run.sh forecast EVENTS_JSON [OUT_JSON]}"
        OUT="${2:-outputs/predictions.json}"
        shift 2 || shift 1 || true
        exec python -m sigma_prophet forecast --events "$EVENTS" -o "$OUT" "$@"
        ;;
    trade)
        exec python -m sigma_prophet trade "$@"
        ;;
    eval)
        EVENTS="${1:?usage: ./run.sh eval RESOLVED_JSON}"
        shift
        exec python -m sigma_prophet eval --events "$EVENTS" "$@"
        ;;
    predict)
        TITLE="${1:?usage: ./run.sh predict TITLE OUTCOMES}"
        OUTCOMES="${2:-Yes,No}"
        shift 2 || shift 1 || true
        exec python -m sigma_prophet predict --title "$TITLE" --outcomes "$OUTCOMES" "$@"
        ;;
    show-config)
        exec python -m sigma_prophet show-config
        ;;
    smoke)
        python -m sigma_prophet show-config
        exec python -m pytest tests -q
        ;;
    pytest)
        exec python -m pytest "$@"
        ;;
    -h|--help|help)
        sed -n '2,15p' "$0"
        ;;
    *)
        exec python -m sigma_prophet "$CMD" "$@"
        ;;
esac
