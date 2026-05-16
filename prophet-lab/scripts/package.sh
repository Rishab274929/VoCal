#!/usr/bin/env bash
# Build a submission-ready zip excluding venv/cache/output.
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$HERE"

OUT="${1:-prophet-lab-submission.zip}"
rm -f "$OUT"

git ls-files 2>/dev/null > .pack-list || true
if [[ ! -s .pack-list ]]; then
    find . \
        -path './.venv' -prune -o \
        -path './outputs' -prune -o \
        -path './.pytest_cache' -prune -o \
        -path './.ruff_cache' -prune -o \
        -name '__pycache__' -prune -o \
        -name '*.pyc' -prune -o \
        -name '.env' -prune -o \
        -name '.DS_Store' -prune -o \
        -type f -print > .pack-list
fi

zip -@ "$OUT" < .pack-list >/dev/null
rm -f .pack-list

echo ">> wrote $OUT ($(du -h "$OUT" | cut -f1))"
