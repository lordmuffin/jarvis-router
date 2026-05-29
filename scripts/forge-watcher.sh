#!/usr/bin/env bash
# Persistent watcher that fires off a Forge session whenever new items
# appear under the "## Active" header in forge-queue.md.
#
# Prefers inotifywait for event-driven wakeups. Falls back to a polling
# loop (FORGE_WATCHER_POLL_INTERVAL seconds) when inotify-tools is not
# available. If neither inotifywait nor the queue file exists, exits 1
# because there is nothing to watch.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

LOG="/tmp/forge-watcher.log"
START_FORGE="$(dirname "$0")/start-forge.sh"

watcher_log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG" >&2
}

have_inotify=0
if command -v inotifywait >/dev/null 2>&1; then
    have_inotify=1
fi

if [[ $have_inotify -eq 0 && ! -f "$FORGE_QUEUE_PATH" ]]; then
    watcher_log "ERROR: inotifywait missing and queue file does not exist ($FORGE_QUEUE_PATH). Nothing to watch."
    exit 1
fi

# Spawn a Forge session if the queue is non-empty and no Forge session
# is already running. Backgrounded so the watcher does not block.
maybe_spawn() {
    if ! active_queue_has_unchecked "$FORGE_QUEUE_PATH"; then
        return 0
    fi
    if tmux_session_alive "$FORGE_TMUX_SESSION"; then
        watcher_log "Active items detected; Forge session already running. Skipping."
        return 0
    fi
    watcher_log "Active items detected. Spawning Forge session."
    nohup bash "$START_FORGE" >>"$LOG" 2>&1 &
}

if [[ $have_inotify -eq 1 ]]; then
    watcher_log "Forge watcher started (inotify mode). Monitoring: $FORGE_QUEUE_PATH"
    # Run an initial check in case items are already queued at boot.
    maybe_spawn
    while true; do
        # If the queue file disappears, inotifywait fails fast; sleep
        # briefly and retry rather than busy-looping.
        if ! inotifywait -qq -e modify,create,close_write "$FORGE_QUEUE_PATH" 2>/dev/null; then
            sleep 5
            continue
        fi
        maybe_spawn
    done
else
    watcher_log "Forge watcher started (degraded poll mode, ${FORGE_WATCHER_POLL_INTERVAL}s). Monitoring: $FORGE_QUEUE_PATH"
    while true; do
        maybe_spawn
        sleep "$FORGE_WATCHER_POLL_INTERVAL"
    done
fi
