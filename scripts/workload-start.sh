#!/usr/bin/env bash
# Unified launcher for on-demand workloads.
#
# Usage:
#   workload-start.sh <forge|transcription|voice> [--cloud]
#
# Resolution order:
#   1. Local tmux session already running → no-op (idempotent)
#   2. --cloud OR a local GPU is busy with another workload → vast-launcher
#   3. Gaming PC available (reachable + k3s-agent inactive) → gaming-pc-launcher
#   4. Local tmux launch via start-<type>.sh (CPU-bound or trusted to run anyway)
#
# This script is also sourced by tests, so all real work lives inside main().

# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WORKLOAD_TYPES=(forge transcription voice)

is_known_workload() {
    local w="$1"
    for t in "${WORKLOAD_TYPES[@]}"; do
        [[ "$t" == "$w" ]] && return 0
    done
    return 1
}

is_gpu_busy() {
    tmux has-session -t forge         2>/dev/null && return 0
    tmux has-session -t transcription 2>/dev/null && return 0
    tmux has-session -t voice         2>/dev/null && return 0
    return 1
}

workload_log_file() {
    printf '/tmp/workload-%s.log\n' "$1"
}

workload_log() {
    local type="$1"; shift
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$(workload_log_file "$type")"
}

local_start_script() {
    local type="$1"
    printf '%s/scripts/start-%s.sh\n' "$REPO_ROOT" "$type"
}

main() {
    if [[ $# -lt 1 ]]; then
        err "usage: workload-start.sh <forge|transcription|voice> [--cloud]"
        exit 2
    fi

    local type="$1"; shift
    local force_cloud=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cloud) force_cloud=1; shift ;;
            *) err "unknown flag: $1"; exit 2 ;;
        esac
    done

    if ! is_known_workload "$type"; then
        err "unknown workload: $type (expected: ${WORKLOAD_TYPES[*]})"
        exit 2
    fi

    load_env

    # 1. Idempotency check — tmux session OR active cloud instance.
    if tmux_session_alive "$type"; then
        log "Workload '$type' already running (local tmux). Nothing to do."
        workload_log "$type" "already running (local)"
        exit 0
    fi
    if [[ -s "/tmp/vast-${type}.instance" ]]; then
        log "Workload '$type' already running on Vast.ai (instance $(cat "/tmp/vast-${type}.instance"))."
        workload_log "$type" "already running (cloud)"
        exit 0
    fi

    # 2. Cloud explicitly requested, or local GPU contention forces cloud.
    if [[ $force_cloud -eq 1 ]] || is_gpu_busy; then
        if [[ $force_cloud -eq 1 ]]; then
            log "Launching '$type' on Vast.ai (--cloud requested)."
        else
            log "Launching '$type' on Vast.ai (local GPU busy)."
        fi
        if "$REPO_ROOT/scripts/vast-launcher.sh" create "$type"; then
            workload_log "$type" "started (cloud)"
            telegram_notify "🚀 ${type} workload started (cloud)" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
            exit 0
        fi
        err "Vast.ai launch failed for $type."
        workload_log "$type" "cloud launch failed"
        telegram_notify "❌ ${type} cloud launch failed — see /tmp/workload-${type}.log" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
        exit 1
    fi

    # 3. Try gaming PC for inference workloads.
    local model="${GAMING_PC_INFERENCE_MODEL:-qwen2.5-coder:14b}"
    if "$REPO_ROOT/scripts/gaming-pc-launcher.sh" available >/dev/null 2>&1; then
        log "Launching '$type' on gaming PC (model: $model)."
        if "$REPO_ROOT/scripts/gaming-pc-launcher.sh" start "$model"; then
            workload_log "$type" "started (gaming-pc, $model)"
            telegram_notify "🖥️ ${type} workload started (gaming PC, ${model})" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
            exit 0
        fi
        warn "Gaming PC launch failed for $type — falling through to local tmux."
    fi

    # 4. Local tmux launch via the workload's start script.
    local starter; starter="$(local_start_script "$type")"
    if [[ ! -x "$starter" ]]; then
        err "No local launcher for workload '$type' at $starter."
        workload_log "$type" "no local launcher and no GPU target — aborting"
        telegram_notify "⚠️ No GPU target available for ${type} workload" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
        exit 1
    fi

    log "Launching '$type' via local tmux ($starter)."
    if "$starter"; then
        workload_log "$type" "started (local)"
        telegram_notify "🚀 ${type} workload started (local)" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
        exit 0
    fi

    err "Local launch failed for $type."
    workload_log "$type" "local launch failed"
    telegram_notify "❌ ${type} local launch failed — see /tmp/workload-${type}.log" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
    exit 1
}

# Only run main when executed directly, not when sourced (tests source us
# to inspect helpers like is_gpu_busy).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
