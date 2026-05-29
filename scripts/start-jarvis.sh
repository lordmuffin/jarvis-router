#!/usr/bin/env bash
# Bring up the Jarvis tmux session running Claude Code with the
# Channels plugin paired to the Telegram bot. Idempotent.
#
# If the session already exists, exits 0 without touching it.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

if tmux_session_alive "$TMUX_SESSION"; then
    log "Session '$TMUX_SESSION' already running. Nothing to do."
    log "Attach: tmux attach -t $TMUX_SESSION  (detach with Ctrl-b d, never Ctrl-c)"
    exit 0
fi

command -v tmux   >/dev/null 2>&1 || die "tmux not found on PATH"
command -v claude >/dev/null 2>&1 || die "claude (Claude Code) not found on PATH"

if [[ ! -d "$JARVIS_PROJECT_DIR" ]]; then
    die "JARVIS_PROJECT_DIR does not exist: $JARVIS_PROJECT_DIR"
fi
if [[ ! -f "$JARVIS_PROJECT_DIR/CLAUDE.md" ]]; then
    warn "No CLAUDE.md at $JARVIS_PROJECT_DIR — Jarvis will start without a routing identity."
fi

# Resolve the bot token so we fail fast if 1Password is locked. We do
# NOT export it into Claude Code's env — the Channels plugin asks for it
# interactively via /telegram:configure. We just verify it can be read.
if [[ -n "$OP_BOT_TOKEN_REF" ]]; then
    log "Verifying bot token can be resolved from 1Password..."
    op_read "$OP_BOT_TOKEN_REF" >/dev/null
    log "Bot token resolves OK (still in 1Password — not written to disk)."
else
    warn "OP_BOT_TOKEN_REF is empty — skipping token check."
fi

log "Starting tmux session '$TMUX_SESSION' in $JARVIS_PROJECT_DIR ..."
tmux new-session -d -s "$TMUX_SESSION" -c "$JARVIS_PROJECT_DIR" "claude"

# Wait for Claude Code to come up (the pane should have output).
elapsed=0
while [[ $elapsed -lt $STARTUP_TIMEOUT ]]; do
    if tmux capture-pane -p -t "$TMUX_SESSION" 2>/dev/null | grep -q '.'; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if ! tmux_session_alive "$TMUX_SESSION"; then
    die "tmux session died during startup. Investigate manually."
fi

log "Session up. Pair the bot if you haven't yet:"
log "  1. tmux attach -t $TMUX_SESSION"
log "  2. In the Claude Code prompt: /plugin install channels  (first time only)"
log "  3. /telegram:configure  -> paste bot token from 1Password"
log "  4. Restart Claude Code (the plugin needs a restart to start polling)"
log "  5. DM the bot in Telegram; paste the 6-char pairing code back"
log "Detach with Ctrl-b d. NEVER Ctrl-c (that kills the session)."
