#!/usr/bin/env bash
# Unified teardown for on-demand workloads.
#
# Usage:
#   workload-stop.sh <forge|transcription|voice>
#
# Tears down BOTH the local tmux session (if any) AND any associated
# Vast.ai instance. Idempotent — runs cleanly when nothing is up.

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

main() {
    if [[ $# -lt 1 ]]; then
        err "usage: workload-stop.sh <forge|transcription|voice>"
        exit 2
    fi

    local type="$1"
    if ! is_known_workload "$type"; then
        err "unknown workload: $type (expected: ${WORKLOAD_TYPES[*]})"
        exit 2
    fi

    load_env

    local stopped_local=0 stopped_cloud=0

    # 1. Local tmux session.
    if tmux has-session -t "$type" 2>/dev/null; then
        log "Stopping local tmux session '$type'."
        tmux kill-session -t "$type" 2>/dev/null || true
        stopped_local=1
    fi

    # 2. Cloud instance (voice is persistent on LXC, no vast instance file).
    local inst_file="/tmp/vast-${type}.instance"
    if [[ -s "$inst_file" ]]; then
        log "Destroying Vast.ai instance for '$type' ($(cat "$inst_file"))."
        if "$REPO_ROOT/scripts/vast-launcher.sh" destroy "$type"; then
            stopped_cloud=1
        else
            warn "Vast.ai destroy returned non-zero — instance may still be running."
        fi
        rm -f "$inst_file"
    fi

    # 3. Voice workload has extra teardown: stop the LXC docker stack.
    if [[ "$type" == "voice" ]] && [[ -x "$REPO_ROOT/scripts/start-voice.sh" ]]; then
        log "Stopping voice docker stack in LXC 400."
        "$REPO_ROOT/scripts/start-voice.sh" stop >/dev/null 2>&1 || \
            warn "voice stack stop returned non-zero — check manually."
    fi

    printf '[%s] stop: local=%d cloud=%d\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$stopped_local" "$stopped_cloud" \
        >> "/tmp/workload-${type}.log"

    if [[ $stopped_local -eq 0 && $stopped_cloud -eq 0 ]]; then
        log "Workload '$type' already stopped — nothing to stop."
        exit 0
    fi

    telegram_notify "🛑 ${type} workload stopped" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
