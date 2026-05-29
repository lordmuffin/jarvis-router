#!/usr/bin/env bash
# Shared helpers for jarvis-router scripts. Source this from every script:
#   # shellcheck source=lib/common.sh
#   . "$(dirname "$0")/lib/common.sh"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

log()  { printf '[jarvis-router] %s\n' "$*" >&2; }
warn() { printf '[jarvis-router][warn] %s\n' "$*" >&2; }
err()  { printf '[jarvis-router][err] %s\n'  "$*" >&2; }
die()  { err "$*"; exit 1; }

# Load .env from the repo root if present. JARVIS_ENV_FILE may override
# the path (used by bats tests).
load_env() {
    local env_file="${JARVIS_ENV_FILE:-${REPO_ROOT}/.env}"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        set -a; . "$env_file"; set +a
    fi

    : "${VAULT_PATH:?VAULT_PATH not set (copy .env.example to .env)}"
    : "${TMUX_SESSION:?TMUX_SESSION not set}"
    : "${JARVIS_PROJECT_DIR:=${VAULT_PATH}/10 Projects/Jarvis}"
    : "${OP_BOT_TOKEN_REF:=}"
    : "${STARTUP_TIMEOUT:=30}"

    export VAULT_PATH TMUX_SESSION JARVIS_PROJECT_DIR OP_BOT_TOKEN_REF STARTUP_TIMEOUT
}

# Resolve a 1Password secret reference. Stdout = the secret. Exits
# non-zero on failure with a useful message.
op_read() {
    local ref="$1"
    [[ -z "$ref" ]] && die "op_read called with empty reference"
    command -v op >/dev/null 2>&1 || die "1Password CLI ('op') not found on PATH"

    if ! op whoami >/dev/null 2>&1; then
        die "1Password CLI is not signed in. Run: op signin"
    fi

    op read "$ref" || die "op read failed for reference: $ref"
}

# Return 0 if a tmux session named "$1" exists, non-zero otherwise.
tmux_session_alive() {
    tmux has-session -t "$1" 2>/dev/null
}

# Today's daily routing log path inside the vault.
todays_routing_log() {
    printf '%s/00 Inbox/jarvis-routing-%s.md\n' "$VAULT_PATH" "$(date +%Y-%m-%d)"
}
