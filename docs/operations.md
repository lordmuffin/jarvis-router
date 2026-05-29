# Operations

Day-to-day commands. For incidents see [runbook.md](runbook.md).

## Start / stop / status

```bash
bash scripts/start-jarvis.sh    # idempotent
bash scripts/stop-jarvis.sh     # idempotent
bash scripts/health-check.sh    # one line + meaningful exit code
```

## Attach to the live session

```bash
tmux attach -t "$TMUX_SESSION"
```

**Detach with `Ctrl-b d`.** Do **NOT** `Ctrl-c` — that kills the
Claude Code process and ends your session. If you do this by accident,
systemd will restart it within 30s but you'll lose any unsaved
conversation state.

## See today's routing decisions

```bash
cat "${VAULT_PATH}/00 Inbox/jarvis-routing-$(date +%Y-%m-%d).md"
```

## Append a manual pattern to routing memory

You normally let Jarvis append these. If you want to seed one by hand:

```bash
echo '[YYYY-MM-DD] pattern: "..." -> persona: <Kai|Forge|Marcus|operator> (confidence: high) -- note: ...' \
  >> "${VAULT_PATH}/10 Projects/Jarvis/routing-memory.md"
```

## systemd

```bash
systemctl --user status jarvis-router
systemctl --user restart jarvis-router
journalctl --user -u jarvis-router -n 200
```

## Forcibly restart from scratch

If you suspect drift between systemd's view and reality:

```bash
systemctl --user stop jarvis-router
bash scripts/stop-jarvis.sh
tmux kill-server                  # nuclear; kills all your tmux sessions
systemctl --user start jarvis-router
```

`tmux kill-server` is destructive to ALL your tmux sessions. Don't run
it unless you understand the blast radius.

## Re-pair the bot

If the bot stops responding but the session is alive, the pairing may
have lapsed:

```bash
tmux attach -t "$TMUX_SESSION"
# Inside Claude Code:
/telegram:configure
# Then restart Claude Code (Ctrl-D / exit, systemd brings it back)
# Then DM the bot a new message and paste the 6-char pairing code
```
