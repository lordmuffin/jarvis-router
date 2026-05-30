#!/usr/bin/env bash
# Watch forge-queue.md for unchecked items under `## Active`. When one
# appears, start-forge.sh launches the session (unless one is already
# running). On hosts without inotify-tools, falls back to a 30s poll
# loop. Designed to run under systemd --user as a long-running service.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

: "${FORGE_TMUX_SESSION:=forge}"
QUEUE="${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md"
WATCH_LOG="/tmp/forge-watcher.log"

watch_log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$WATCH_LOG" >&2
}

active_has_unchecked() {
    [[ -f "$QUEUE" ]] || return 1
    awk '/^## Active/{found=1; next} found && /^## /{found=0} found && /^- \[ \]/{exit 0} END{exit 1}' "$QUEUE"
}

trigger_if_needed() {
    if active_has_unchecked; then
        if tmux_session_alive "$FORGE_TMUX_SESSION"; then
            watch_log "Active items detected, Forge session already running. Skipping."
        else
            watch_log "Active items detected. Starting Forge session."
            "$(dirname "$0")/start-forge.sh" >> "$WATCH_LOG" 2>&1 || \
                watch_log "start-forge.sh exited non-zero."
        fi
    fi
}

# Fail-fast if neither inotifywait nor the queue file is present — without
# both, the script would loop forever doing nothing useful.
if ! command -v inotifywait >/dev/null 2>&1 && [[ ! -f "$QUEUE" ]]; then
    err "Neither inotifywait nor queue file ($QUEUE) is available. Install inotify-tools or create the queue file."
    exit 1
fi

watch_log "Forge watcher started. Monitoring: $QUEUE"

if command -v inotifywait >/dev/null 2>&1; then
    # Event-driven path. inotifywait blocks until the file is modified.
    while true; do
        inotifywait -e modify,create,close_write "$QUEUE" >/dev/null 2>&1 || {
            sleep 5
            continue
        }
        trigger_if_needed
    done
else
    warn "inotifywait not found — falling back to 30s poll loop (degraded mode)."
    while true; do
        trigger_if_needed
        sleep 30
    done
fi
