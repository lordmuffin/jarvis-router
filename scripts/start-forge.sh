#!/usr/bin/env bash
# Launch and supervise a Forge work session.
#
# Forge is the on-demand work agent. Unlike the always-on Kai session,
# a Forge session runs to completion (Type=oneshot) and is not
# auto-restarted by systemd. The watcher (forge-watcher.sh) spawns this
# script whenever forge-queue.md's "## Active" section gets new items.
#
# On a clean exit (Active section empty when tmux session ends) the
# script returns 0. On a crash (Active section still has unchecked
# items when the session dies) the script:
#   1. records the in-flight task under "## Paused" in forge-queue.md,
#   2. DMs Andrew via the ForgeBot Telegram bot,
#   3. exits non-zero so the systemd unit records failure.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

LOG="/tmp/forge-start.log"

log_event() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG" >&2
}

# Idempotent: if a Forge session is already up, do nothing.
if tmux_session_alive "$FORGE_TMUX_SESSION"; then
    log "Forge session '$FORGE_TMUX_SESSION' already running. Nothing to do."
    exit 0
fi

command -v tmux   >/dev/null 2>&1 || die "tmux not found on PATH"
command -v claude >/dev/null 2>&1 || die "claude (Claude Code) not found on PATH"
command -v curl   >/dev/null 2>&1 || warn "curl not on PATH — Telegram crash notifications will be skipped."

if [[ ! -d "$FORGE_PROJECT_DIR" ]]; then
    die "FORGE_PROJECT_DIR does not exist: $FORGE_PROJECT_DIR"
fi

# Verify ForgeBot token can be resolved if a reference is configured.
if [[ -n "$FORGE_OP_BOT_TOKEN_REF" ]]; then
    log "Verifying ForgeBot token can be resolved from 1Password..."
    op_read "$FORGE_OP_BOT_TOKEN_REF" >/dev/null
    log "ForgeBot token resolves OK."
else
    warn "FORGE_OP_BOT_TOKEN_REF is empty — crash notifications disabled."
fi

# Build the claude argv. --system-prompt is optional; if the file is
# missing we let Claude Code load CLAUDE.md from FORGE_PROJECT_DIR.
claude_cmd=("claude")
if [[ -n "${FORGE_SYSTEM_PROMPT:-}" && -f "$FORGE_SYSTEM_PROMPT" ]]; then
    claude_cmd=("claude" "--system-prompt" "$FORGE_SYSTEM_PROMPT")
fi

log "Starting Forge tmux session '$FORGE_TMUX_SESSION' in $FORGE_PROJECT_DIR ..."
tmux new-session -d -s "$FORGE_TMUX_SESSION" -c "$FORGE_PROJECT_DIR" "${claude_cmd[@]}"

# Post-launch verification: tmux should report has-session within
# FORGE_STARTUP_TIMEOUT seconds.
elapsed=0
launched=0
while [[ $elapsed -lt $FORGE_STARTUP_TIMEOUT ]]; do
    if tmux_session_alive "$FORGE_TMUX_SESSION"; then
        launched=1
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if [[ $launched -eq 0 ]]; then
    log_event "forge session failed to start: tmux has-session not found within ${FORGE_STARTUP_TIMEOUT}s"
    exit 1
fi

log_event "forge session started successfully (RUNNING as '$FORGE_TMUX_SESSION')"

# Block until the session ends. Polling rather than tmux wait-for so
# we don't depend on a signaler being wired up inside the Claude pane.
while tmux_session_alive "$FORGE_TMUX_SESSION"; do
    sleep 1
done

log "Forge tmux session has ended; checking queue state."

# Read the first unchecked Active item BEFORE we modify the file.
last_task="$(awk '
    /^## Active/ { found = 1; next }
    found && /^## / { found = 0 }
    found && /^- \[ \]/ { print; exit }
' "$FORGE_QUEUE_PATH" 2>/dev/null || true)"

if active_queue_has_unchecked "$FORGE_QUEUE_PATH"; then
    # --- crash path ----------------------------------------------------
    if grep -q '^## Paused' "$FORGE_QUEUE_PATH"; then
        # Append under the existing Paused header.
        tmp="$(mktemp)"
        awk -v task="$last_task" '
            /^## Paused/ { print; print task; next }
            { print }
        ' "$FORGE_QUEUE_PATH" > "$tmp" && mv "$tmp" "$FORGE_QUEUE_PATH"
    else
        printf '\n## Paused\n%s\n' "$last_task" >> "$FORGE_QUEUE_PATH"
    fi

    msg="Forge session crashed before completing: ${last_task:-(unknown task)}. Reply 'resume' or 'skip'."
    if ! notify_telegram "$FORGE_TELEGRAM_CHAT_ID" "$msg"; then
        warn "telegram notification failed; crash recorded in forge-queue.md only."
    fi

    log_event "forge session ended with unchecked Active items; paused: ${last_task:-unknown}"
    exit 1
fi

# --- clean path --------------------------------------------------------
log_event "forge session completed cleanly (queue Active section is empty)"
exit 0
