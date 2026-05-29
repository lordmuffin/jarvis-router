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

## Forge agent

Forge is an on-demand work agent that runs in its own tmux session
(`$FORGE_TMUX_SESSION`, default `forge`) under a dedicated bot
identity (ForgeBot). It is **not** held alive like Kai — each session
runs until the queue is empty and then exits.

### How Forge gets triggered

Kai appends items under `## Active` in
`${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md`. A
persistent watcher (`forge-watcher.service`) sees the file change and
spawns `scripts/start-forge.sh` in the background. The watcher will
not spawn a second session if one is already running.

### Start / stop manually

```bash
bash scripts/start-forge.sh                  # one-off, foreground
systemctl --user start forge-session.service # one-off, via systemd
tmux attach -t forge                         # peek at the live pane
tmux kill-session -t forge                   # force stop (treated as a crash)
```

### Check status

```bash
bash scripts/health-check.sh
# ... forge: RUNNING | forge-watcher: active
# ... forge-watcher.log (last 3): ...
```

### Logs

```bash
journalctl --user -u forge-watcher -f   # watcher daemon
journalctl --user -u forge-session -n 200  # last manual oneshot run
tail -f /tmp/forge-start.log            # per-launch start verdicts
tail -f /tmp/forge-watcher.log          # watcher state transitions
```

### Crash recovery

If `start-forge.sh` exits while `## Active` still has unchecked items,
it treats the run as a crash:

1. The in-flight task is appended under `## Paused` in
   `forge-queue.md` (header is created if missing; appended under if
   already present).
2. ForgeBot DMs `$FORGE_TELEGRAM_CHAT_ID` with the task and a "reply
   'resume' or 'skip'" prompt.
3. The watcher does **not** auto-respawn — it waits for the queue to
   change again (you decide whether to move the task back under
   `## Active` or leave it parked).
