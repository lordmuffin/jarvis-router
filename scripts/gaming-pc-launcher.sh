#!/usr/bin/env bash
# Manage Ollama on Andrew's gaming PC (RX 9070 XT, CachyOS) over SSH.
#
# Subcommands:
#   start <model>  → SSH in, ensure `ollama serve` is running, pull model if needed
#   stop           → SSH in, kill `ollama serve`
#   status         → curl GET /api/tags, exit 0 if responsive
#   available      → 0 iff host is reachable AND k3s-agent is inactive
#                    (gaming mode = GPU free for inference)
#
# Env (from .env):
#   GAMING_PC_HOST            hostname or IP (required)
#   GAMING_PC_SSH_KEY         path to private key (optional)
#   GAMING_PC_INFERENCE_MODEL default model (optional)
#
# On successful start, writes endpoint URL to /tmp/gaming-pc-inference.endpoint
# and best-effort notifies Telegram.

# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ENDPOINT_FILE="/tmp/gaming-pc-inference.endpoint"
OLLAMA_PORT=11434
SSH_TIMEOUT=5

# Load env; don't require it if just inspecting (e.g., status with no host).
load_env_if_present() {
    local env_file="${JARVIS_ENV_FILE:-${REPO_ROOT}/.env}"
    if [[ -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
    fi
}

require_host() {
    if [[ -z "${GAMING_PC_HOST:-}" ]]; then
        err "GAMING_PC_HOST not set in .env. Cannot reach gaming PC."
        exit 1
    fi
}

ssh_args() {
    local args=(-o "ConnectTimeout=${SSH_TIMEOUT}" -o "BatchMode=yes" -o "StrictHostKeyChecking=accept-new")
    if [[ -n "${GAMING_PC_SSH_KEY:-}" ]]; then
        args+=(-i "$GAMING_PC_SSH_KEY")
    fi
    printf '%s\n' "${args[@]}"
}

ssh_exec() {
    local -a args
    mapfile -t args < <(ssh_args)
    # SC2029: intentional — the command string is meant to expand on the
    # remote host, not locally.
    # shellcheck disable=SC2029
    ssh "${args[@]}" "$GAMING_PC_HOST" "$@"
}

cmd_status() {
    require_host
    local url="http://${GAMING_PC_HOST}:${OLLAMA_PORT}/api/tags"
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
        log "ollama responsive at $url"
        exit 0
    fi
    warn "ollama not responding at $url"
    exit 1
}

cmd_available() {
    require_host
    # Reachability: try TCP connection to SSH port; cheaper than full ssh.
    if ! command -v nc >/dev/null 2>&1; then
        warn "nc not on PATH — falling back to ssh probe for reachability"
        ssh_exec "true" >/dev/null 2>&1 || exit 1
    else
        nc -z -w "$SSH_TIMEOUT" "$GAMING_PC_HOST" 22 >/dev/null 2>&1 || exit 1
    fi
    # Gaming mode = k3s-agent stopped/inactive.
    local k3s_state
    k3s_state="$(ssh_exec "systemctl is-active k3s-agent 2>/dev/null || echo unknown" 2>/dev/null || echo unknown)"
    if [[ "$k3s_state" == "inactive" ]]; then
        log "gaming PC available (k3s-agent inactive)"
        exit 0
    fi
    log "gaming PC NOT available (k3s-agent: $k3s_state)"
    exit 1
}

cmd_start() {
    require_host
    local model="${1:-${GAMING_PC_INFERENCE_MODEL:-qwen2.5-coder:14b}}"

    log "Ensuring ollama serve is running on $GAMING_PC_HOST ..."
    ssh_exec "pgrep -f 'ollama serve' >/dev/null 2>&1 || (nohup ollama serve >/tmp/ollama.log 2>&1 &) ; sleep 1" \
        || die "Failed to start ollama serve on $GAMING_PC_HOST"

    log "Ensuring model '$model' is pulled ..."
    ssh_exec "ollama list 2>/dev/null | grep -q '^$(printf '%s' "$model" | sed 's/:/[: ]/g')' || ollama pull '$model'" \
        || die "Failed to pull model $model"

    local url="http://${GAMING_PC_HOST}:${OLLAMA_PORT}"
    local elapsed=0 max=60
    while [[ $elapsed -lt $max ]]; do
        if curl -fsS --max-time 3 "${url}/api/tags" >/dev/null 2>&1; then
            printf '%s\n' "$url" > "$ENDPOINT_FILE"
            log "gaming PC inference ready: $model at $url"
            telegram_notify "🖥️ Gaming PC inference ready: ${model} at ${url}" \
                "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
            exit 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    die "ollama did not become responsive at $url within ${max}s"
}

cmd_stop() {
    require_host
    log "Stopping ollama serve on $GAMING_PC_HOST ..."
    ssh_exec "pkill -f 'ollama serve' 2>/dev/null || true" || true
    rm -f "$ENDPOINT_FILE"
    log "ollama stopped (endpoint file cleared)"
    exit 0
}

main() {
    if [[ $# -lt 1 ]]; then
        err "usage: gaming-pc-launcher.sh <start|stop|status|available> [model]"
        exit 2
    fi
    load_env_if_present

    case "$1" in
        start)     shift; cmd_start "$@" ;;
        stop)      cmd_stop ;;
        status)    cmd_status ;;
        available) cmd_available ;;
        *) err "usage: gaming-pc-launcher.sh <start|stop|status|available> [model]"; exit 2 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
