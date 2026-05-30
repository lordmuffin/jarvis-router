#!/usr/bin/env bash
# Lint + test wrapper. Run before every commit.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if command -v shellcheck >/dev/null 2>&1; then
    echo "==> shellcheck"
    # Lint .sh files only — bats files have their own syntax. -x follows
    # `. lib/common.sh` so sourced helpers don't trip SC1091.
    find scripts -name '*.sh' -print0 | xargs -0 shellcheck -x
else
    echo "shellcheck not found; skipping lint" >&2
fi

if command -v bats >/dev/null 2>&1; then
    echo "==> bats"
    bats tests/
else
    echo "bats not found; skipping tests" >&2
    exit 1
fi
