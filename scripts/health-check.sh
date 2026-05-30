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
        ;;
    degraded)
        warn "degraded: ${reasons[*]}"
        ;;
    dead)
        err "dead: ${reasons[*]}"
        ;;
esac

# === Workloads ===
print_workload() {
    local name="$1"
    if tmux_session_alive "$name"; then
        printf '%-14s RUNNING\n' "${name}:" >&2
    else
        printf '%-14s idle\n'    "${name}:" >&2
    fi
}

printf '\n=== Workloads ===\n' >&2
print_workload forge
print_workload transcription
print_workload voice

# === Forge watcher (last 3 lines if log exists) ===
if [[ -f /tmp/forge-watcher.log ]]; then
    printf '\n=== Forge watcher (tail) ===\n' >&2
    tail -n 3 /tmp/forge-watcher.log >&2 || true
fi

# === Cloud GPU ===
printf '\n=== Cloud GPU ===\n' >&2
for type in forge transcription voice; do
    f="/tmp/vast-${type}.instance"
    if [[ -s "$f" ]]; then
        printf '%-22s %s\n' "vast.ai ${type}:" "$(cat "$f")" >&2
    else
        printf '%-22s none\n' "vast.ai ${type}:" >&2
    fi
done

# === GPU Utilization (nvidia-smi if present; gaming PC ollama endpoint) ===
if command -v nvidia-smi >/dev/null 2>&1; then
    printf '\n=== GPU Utilization ===\n' >&2
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu \
        --format=csv,noheader 2>/dev/null >&2 || true
fi
if [[ -s /tmp/gaming-pc-inference.endpoint ]]; then
    printf '\n=== Gaming PC inference ===\n' >&2
    printf 'endpoint: %s\n' "$(cat /tmp/gaming-pc-inference.endpoint)" >&2
fi

case "$status" in
    ok)       exit 0 ;;
    degraded) exit 1 ;;
    dead)     exit 2 ;;
esac
