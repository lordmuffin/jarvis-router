#!/usr/bin/env bash
# Manage the voice docker stack (Kokoro TTS + XTTS) hosted in LXC 400 on
# the Proxmox node. Persistent — stays up until explicitly stopped via
# `start-voice.sh stop` (or via workload-stop.sh voice).
#
# Subcommands (default: start):
#   start    docker-compose start; poll Kokoro (8880) + XTTS (8881) until green
#   stop     docker-compose stop
#   status   curl both health endpoints, exit 0 if both green
#
# Voice is controlled remotely — either via `pct exec 400 --` on the
# Proxmox host or via SSH to a host already on the LXC bridge. Andrew's
# setup uses Proxmox at 192.168.1.101.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

: "${VOICE_TMUX_SESSION:=voice}"
: "${PROXMOX_HOST:=192.168.1.101}"
: "${PROXMOX_SSH_KEY:=}"
: "${VOICE_LXC_ID:=400}"
: "${VOICE_COMPOSE_DIR:=/opt/voice}"
: "${KOKORO_PORT:=8880}"
: "${XTTS_PORT:=8881}"
: "${TELEGRAM_CHAT_ID:=}"

VOICE_HOST="${VOICE_HOST:-${PROXMOX_HOST}}"

ssh_proxmox() {
    local -a args=(-o "ConnectTimeout=5" -o "BatchMode=yes" -o "StrictHostKeyChecking=accept-new")
    if [[ -n "$PROXMOX_SSH_KEY" ]]; then
        args+=(-i "$PROXMOX_SSH_KEY")
    fi
    ssh "${args[@]}" "$PROXMOX_HOST" "$@"
}

# Run a command inside LXC 400. Prefers `pct exec` (run from Proxmox host);
# falls back to running directly if VOICE_DIRECT=1 (e.g., this script is
# invoked from inside the LXC for testing).
lxc_exec() {
    local cmd="$1"
    if [[ "${VOICE_DIRECT:-0}" == "1" ]]; then
        bash -c "$cmd"
    else
        ssh_proxmox "pct exec $VOICE_LXC_ID -- bash -lc '$cmd'"
    fi
}

ports_healthy() {
    curl -fsS --max-time 3 "http://${VOICE_HOST}:${KOKORO_PORT}/health" >/dev/null 2>&1 || \
    curl -fsS --max-time 3 "http://${VOICE_HOST}:${KOKORO_PORT}/" >/dev/null 2>&1 || return 1
    curl -fsS --max-time 3 "http://${VOICE_HOST}:${XTTS_PORT}/health" >/dev/null 2>&1 || \
    curl -fsS --max-time 3 "http://${VOICE_HOST}:${XTTS_PORT}/" >/dev/null 2>&1 || return 1
    return 0
}

cmd_start() {
    if tmux_session_alive "$VOICE_TMUX_SESSION"; then
        log "Voice session marker '$VOICE_TMUX_SESSION' already exists."
    fi

    log "Starting voice stack in LXC ${VOICE_LXC_ID} via $PROXMOX_HOST ..."
    lxc_exec "cd $VOICE_COMPOSE_DIR && docker compose start 2>/dev/null || docker-compose start" \
        || die "Failed to start docker stack in LXC $VOICE_LXC_ID"

    log "Polling Kokoro :${KOKORO_PORT} and XTTS :${XTTS_PORT} for readiness ..."
    local elapsed=0 max=60
    while [[ $elapsed -lt $max ]]; do
        if ports_healthy; then
            # Marker tmux session so health-check.sh and workload-start.sh
            # see this workload as "running".
            if ! tmux_session_alive "$VOICE_TMUX_SESSION"; then
                tmux new-session -d -s "$VOICE_TMUX_SESSION" "sleep infinity"
            fi
            log "Voice stack is green (Kokoro + XTTS responsive)."
            telegram_notify "🔊 Voice stack ready (LXC ${VOICE_LXC_ID})" \
                "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
            exit 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    err "Voice stack did not become healthy within ${max}s."
    telegram_notify "❌ Voice stack failed to become healthy in ${max}s" \
        "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
    exit 1
}

cmd_stop() {
    log "Stopping voice stack in LXC ${VOICE_LXC_ID} ..."
    lxc_exec "cd $VOICE_COMPOSE_DIR && docker compose stop 2>/dev/null || docker-compose stop" \
        || warn "docker compose stop returned non-zero — check manually."
    if tmux_session_alive "$VOICE_TMUX_SESSION"; then
        tmux kill-session -t "$VOICE_TMUX_SESSION" 2>/dev/null || true
    fi
    log "Voice stack stopped."
    exit 0
}

cmd_status() {
    if ports_healthy; then
        log "voice: healthy (Kokoro + XTTS responsive at $VOICE_HOST)"
        exit 0
    fi
    warn "voice: unhealthy (one or both endpoints down)"
    exit 1
}

case "${1:-start}" in
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    *) err "usage: start-voice.sh [start|stop|status]"; exit 2 ;;
esac
