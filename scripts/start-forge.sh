#!/usr/bin/env bash
# Bring up the Forge tmux session running Claude Code with the ForgeBot
# Telegram identity. Idempotent and oneshot — Forge runs until the queue
# is empty, then exits. Do NOT auto-restart on clean exit.
#
# On idempotent hit (session already alive) we exit 0 with no side effects.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

# Forge-specific settings (separate session name + token from Kai).
: "${FORGE_TMUX_SESSION:=forge}"
: "${FORGE_OP_BOT_TOKEN_REF:=}"
: "${TELEGRAM_CHAT_ID:=}"

FORGE_SYSTEM_PROMPT="${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-system-prompt.md"
FORGE_LOG="/tmp/forge-start.log"

forge_log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$FORGE_LOG"
}

if tmux_session_alive "$FORGE_TMUX_SESSION"; then
    log "Forge session '$FORGE_TMUX_SESSION' already running. Nothing to do."
    forge_log "already running: $FORGE_TMUX_SESSION"
    exit 0
fi

command -v tmux   >/dev/null 2>&1 || die "tmux not found on PATH"
command -v claude >/dev/null 2>&1 || die "claude (Claude Code) not found on PATH"

if [[ ! -d "$VAULT_PATH" ]]; then
    die "VAULT_PATH does not exist: $VAULT_PATH"
fi

# Resolve the ForgeBot token (fail-fast on 1Password issues). Not exported
# into the session — the Channels plugin asks for it interactively.
if [[ -n "$FORGE_OP_BOT_TOKEN_REF" ]]; then
    log "Verifying ForgeBot token can be resolved from 1Password..."
    op_read "$FORGE_OP_BOT_TOKEN_REF" >/dev/null
    log "ForgeBot token resolves OK."
else
    warn "FORGE_OP_BOT_TOKEN_REF is empty — skipping token check."
fi

# Pass --system-prompt only if the file exists AND the flag is supported.
# We probe by checking `claude --help` for the flag; some Claude Code
# versions don't have it, in which case CLAUDE.md in the vault drives behavior.
claude_args=()
if [[ -f "$FORGE_SYSTEM_PROMPT" ]] && claude --help 2>/dev/null | grep -q -- '--system-prompt'; then
    claude_args+=(--system-prompt "$FORGE_SYSTEM_PROMPT")
else
    if [[ ! -f "$FORGE_SYSTEM_PROMPT" ]]; then
        warn "No forge-system-prompt.md at $FORGE_SYSTEM_PROMPT — Forge will rely on vault CLAUDE.md."
    fi
fi

log "Starting tmux session '$FORGE_TMUX_SESSION' in $VAULT_PATH ..."
if [[ ${#claude_args[@]} -gt 0 ]]; then
    tmux new-session -d -s "$FORGE_TMUX_SESSION" -c "$VAULT_PATH" \
        "claude ${claude_args[*]}"
else
    tmux new-session -d -s "$FORGE_TMUX_SESSION" -c "$VAULT_PATH" "claude"
fi

# Post-launch verification: tmux should have the session within 10s.
elapsed=0
while [[ $elapsed -lt 10 ]]; do
    if tmux_session_alive "$FORGE_TMUX_SESSION"; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if tmux_session_alive "$FORGE_TMUX_SESSION"; then
    log "Forge session up."
    forge_log "started: $FORGE_TMUX_SESSION"
    exit 0
fi

# Crash path: write Paused section to the queue (best-effort) and notify.
forge_log "failed: $FORGE_TMUX_SESSION did not come up within 10s"
err "Forge session failed to start within 10s."
telegram_notify "Forge crashed at startup — session '$FORGE_TMUX_SESSION' never came up. Investigate before resuming." "$TELEGRAM_CHAT_ID" "$FORGE_OP_BOT_TOKEN_REF"

queue="${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md"
if [[ -f "$queue" ]]; then
    {
        echo ""
        echo "## Paused"
        echo "- [ ] (forge start failed at $(date -Iseconds) — investigate)"
    } >> "$queue"
fi

exit 1
