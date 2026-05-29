#!/usr/bin/env bash
# Stop the Jarvis tmux session gracefully. Idempotent.
#
# Strategy: send /exit + Enter to the Claude Code prompt, wait up to 10s
# for the session to die, then kill-session as fallback.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

if ! tmux_session_alive "$TMUX_SESSION"; then
    log "Session '$TMUX_SESSION' is already stopped."
    exit 0
fi

log "Asking Claude Code to exit gracefully..."
tmux send-keys -t "$TMUX_SESSION" "/exit" Enter 2>/dev/null || true

elapsed=0
while [[ $elapsed -lt 10 ]]; do
    if ! tmux_session_alive "$TMUX_SESSION"; then
        log "Session exited cleanly."
        exit 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

warn "Graceful exit timed out. Killing session."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

if tmux_session_alive "$TMUX_SESSION"; then
    die "Failed to kill session '$TMUX_SESSION'."
fi

log "Session killed."
