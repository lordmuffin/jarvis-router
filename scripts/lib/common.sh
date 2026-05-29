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

    : "${FORGE_TMUX_SESSION:=forge}"
    : "${FORGE_PROJECT_DIR:=${VAULT_PATH}}"
    : "${FORGE_QUEUE_PATH:=${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md}"
    : "${FORGE_SYSTEM_PROMPT:=${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-system-prompt.md}"
    : "${FORGE_OP_BOT_TOKEN_REF:=}"
    : "${FORGE_TELEGRAM_CHAT_ID:=7024287135}"
    : "${FORGE_WATCHER_POLL_INTERVAL:=30}"
    : "${FORGE_STARTUP_TIMEOUT:=10}"

    export VAULT_PATH TMUX_SESSION JARVIS_PROJECT_DIR OP_BOT_TOKEN_REF STARTUP_TIMEOUT
    export FORGE_TMUX_SESSION FORGE_PROJECT_DIR FORGE_QUEUE_PATH FORGE_SYSTEM_PROMPT
    export FORGE_OP_BOT_TOKEN_REF FORGE_TELEGRAM_CHAT_ID FORGE_WATCHER_POLL_INTERVAL
    export FORGE_STARTUP_TIMEOUT
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

# Return 0 if the file at "$1" contains an unchecked "- [ ]" item inside
# its "## Active" section, non-zero otherwise. Used by forge-watcher to
# decide when to spawn a Forge session and by start-forge.sh to detect
# whether a session crashed mid-task.
#
# Note: the awk pattern uses `hit=1; exit` with `END{exit !hit}` rather
# than `exit 0` / `END{exit 1}` because awk runs the END block after any
# `exit`, and a second `exit` in END overrides the earlier status.
active_queue_has_unchecked() {
    local path="$1"
    [[ -f "$path" ]] || return 1
    awk '
        /^## Active/ { found = 1; next }
        found && /^## / { found = 0 }
        found && /^- \[ \]/ { hit = 1; exit }
        END { exit !hit }
    ' "$path"
}

# POST a sendMessage to the Telegram Bot API. Arg 1 = chat id, arg 2 =
# message text. Pulls the token from FORGE_OP_BOT_TOKEN_REF via op_read.
# Returns non-zero on any failure (missing token ref, op locked, curl
# failure) but does not die() — callers in crash paths must still exit
# with the crash status even if notification fails.
notify_telegram() {
    local chat_id="$1"
    local text="$2"

    if [[ -z "${FORGE_OP_BOT_TOKEN_REF:-}" ]]; then
        warn "FORGE_OP_BOT_TOKEN_REF empty; skipping Telegram notify."
        return 1
    fi

    local token
    if ! token="$(op_read "$FORGE_OP_BOT_TOKEN_REF" 2>/dev/null)"; then
        warn "could not resolve Forge bot token; skipping Telegram notify."
        return 1
    fi

    command -v curl >/dev/null 2>&1 || { warn "curl not on PATH; skipping Telegram notify."; return 1; }

    curl -sS -X POST \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        "https://api.telegram.org/bot${token}/sendMessage" \
        >/dev/null
}
