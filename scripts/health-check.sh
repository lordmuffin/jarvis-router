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

# Forge status is informational only. It is printed alongside Kai's
# status but does not influence the exit code — Forge being idle is
# the steady state (the watcher only spawns it when there's work).
report_forge_status() {
    local forge_state="idle"
    if tmux_session_alive "$FORGE_TMUX_SESSION"; then
        forge_state="RUNNING"
    fi

    local watcher_state="unknown"
    if command -v systemctl >/dev/null 2>&1; then
        watcher_state="$(systemctl --user is-active forge-watcher.service 2>/dev/null || true)"
        [[ -z "$watcher_state" ]] && watcher_state="unknown"
    fi

    log "forge: $forge_state | forge-watcher: $watcher_state"

    if [[ -f /tmp/forge-watcher.log ]]; then
        log "forge-watcher.log (last 3):"
        tail -n 3 /tmp/forge-watcher.log | while IFS= read -r line; do
            log "  $line"
        done
    fi
}

case "$status" in
    ok)
        if [[ ${#reasons[@]} -gt 0 ]]; then
            log "ok (${reasons[*]})"
        else
            log "ok"
        fi
        report_forge_status
        exit 0
        ;;
    degraded)
        warn "degraded: ${reasons[*]}"
        report_forge_status
        exit 1
        ;;
    dead)
        err "dead: ${reasons[*]}"
        report_forge_status
        exit 2
        ;;
esac
