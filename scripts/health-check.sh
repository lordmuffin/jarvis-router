#!/usr/bin/env bash
# One-line status for Jarvis. Exit 0 if healthy, non-zero otherwise.
# Used by systemd ExecStartPost and by Andrew manually.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

status="ok"
reasons=()

if ! tmux_session_alive "$TMUX_SESSION"; then
    status="dead"
    reasons+=("tmux session '$TMUX_SESSION' is not running")
fi

# If the session is alive, glance at the pane for obvious error markers.
# This is best-effort; absence of errors does not prove health.
if [[ "$status" = "ok" ]]; then
    pane="$(tmux capture-pane -p -t "$TMUX_SESSION" 2>/dev/null || true)"
    if grep -qiE 'error|exception|not authenticated|pairing failed' <<<"$pane"; then
        status="degraded"
        reasons+=("pane shows error-looking output")
    fi
fi

# Soft signal: if it's past 9am local time and today's routing log
# doesn't exist yet, mention it. Warning only, not a failure.
today_log="$(todays_routing_log)"
if [[ "$status" = "ok" && $(date +%H) -ge 9 && ! -f "$today_log" ]]; then
    reasons+=("note: today's routing log not yet created ($today_log)")
fi

case "$status" in
    ok)
        if [[ ${#reasons[@]} -gt 0 ]]; then
            log "ok (${reasons[*]})"
        else
            log "ok"
        fi
        exit 0
        ;;
    degraded)
        warn "degraded: ${reasons[*]}"
        exit 1
        ;;
    dead)
        err "dead: ${reasons[*]}"
        exit 2
        ;;
esac
