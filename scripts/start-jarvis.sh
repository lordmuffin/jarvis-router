#!/usr/bin/env bash
# Bring up the Jarvis tmux session running Claude Code with the
# Channels plugin paired to the Telegram bot. Idempotent.
#
# If the session already exists, exits 0 without touching it.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

# systemd strips ~/.bun/bin and ~/.local/bin from PATH. The Telegram
# channel plugin spawns its MCP server via `bun`; without bun on PATH
# the spawn fails with ENOENT and the bot never comes online.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"

if tmux_session_alive "$TMUX_SESSION"; then
    log "Session '$TMUX_SESSION' already running. Nothing to do."
    log "Attach: tmux attach -t $TMUX_SESSION  (detach with Ctrl-b d, never Ctrl-c)"
    exit 0
fi

command -v tmux   >/dev/null 2>&1 || die "tmux not found on PATH"
command -v claude >/dev/null 2>&1 || die "claude (Claude Code) not found on PATH"
command -v bun    >/dev/null 2>&1 || die "bun not found on PATH — the Telegram channel plugin needs bun to spawn its MCP server. Install via: curl -fsSL https://bun.sh/install | bash"

if [[ ! -d "$JARVIS_PROJECT_DIR" ]]; then
    die "JARVIS_PROJECT_DIR does not exist: $JARVIS_PROJECT_DIR"
fi
if [[ ! -f "$JARVIS_PROJECT_DIR/CLAUDE.md" ]]; then
    warn "No CLAUDE.md at $JARVIS_PROJECT_DIR — Jarvis will start without a routing identity."
fi

# Materialize the bot token from 1Password into the file the Channels
# plugin's MCP server reads at boot (~/.claude/channels/telegram/.env).
#
# The plugin's .env loader is a literal regex parser — it does NOT expand
# $(...), `op read`, or `op://` references. So we resolve the secret here
# and write the plain token via a temp-file rename so a partial write can
# never leave a truncated credential on disk. Single key, no quotes — the
# parser hands the entire RHS to grammy as the token.
if [[ -n "$OP_BOT_TOKEN_REF" ]]; then
    log "Resolving bot token from 1Password..."
    token="$(op_read "$OP_BOT_TOKEN_REF")"
    if [[ -z "$token" ]]; then
        die "op read returned an empty token for $OP_BOT_TOKEN_REF"
    fi

    channels_dir="$HOME/.claude/channels/telegram"
    channels_env="$channels_dir/.env"
    mkdir -p "$channels_dir"
    chmod 700 "$channels_dir"

    tmp_env="$(mktemp "$channels_dir/.env.XXXXXX")"
    chmod 600 "$tmp_env"
    printf 'TELEGRAM_BOT_TOKEN=%s\n' "$token" > "$tmp_env"
    mv "$tmp_env" "$channels_env"
    unset token

    log "Bot token written to $channels_env (0600, single key)."
else
    warn "OP_BOT_TOKEN_REF is empty — skipping token materialization."
    if [[ ! -s "$HOME/.claude/channels/telegram/.env" ]]; then
        warn "No bot token at ~/.claude/channels/telegram/.env either."
        warn "Bot will not come online until you set OP_BOT_TOKEN_REF or run /telegram:configure inside the session."
    fi
fi

log "Starting tmux session '$TMUX_SESSION' in $JARVIS_PROJECT_DIR ..."
tmux new-session -d -s "$TMUX_SESSION" -c "$JARVIS_PROJECT_DIR" "claude --channels plugin:telegram@claude-plugins-official"

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

log "Session up with Telegram channel plugin loaded."
if [[ -n "$OP_BOT_TOKEN_REF" ]]; then
    log "Bot token materialized from 1Password. If this host has never paired before:"
    log "  1. DM the bot in Telegram"
    log "  2. Claude Code prints a 6-char pairing code in the tmux pane — paste it back to the bot"
    log "Attach with: tmux attach -t $TMUX_SESSION  (detach Ctrl-b d, NEVER Ctrl-c)"
else
    log "No OP_BOT_TOKEN_REF set. To bring the bot online:"
    log "  1. tmux attach -t $TMUX_SESSION"
    log "  2. /telegram:configure  -> paste bot token from 1Password"
    log "  3. Restart Claude Code (the plugin needs a restart to start polling)"
    log "  4. DM the bot in Telegram; paste the 6-char pairing code back"
    log "Detach with Ctrl-b d. NEVER Ctrl-c (that kills the session)."
fi
