# Runbook

Incident playbook. Each scenario: symptom → diagnosis → fix.

## tmux session dead but `systemctl --user status` says active

**Symptom.** `tmux has-session -t "$TMUX_SESSION"` returns non-zero
but systemd reports `active (running)`.

**Diagnosis.** The unit file forks (Claude Code under tmux) and systemd
isn't tracking the tmux session directly. `ExecStartPost` ran a
`health-check.sh` that passed at the time, but the session died after.

**Fix.**

```bash
systemctl --user restart jarvis-router
bash scripts/health-check.sh
```

If it dies again immediately, attach during startup
(`tmux attach -t "$TMUX_SESSION"` in a separate terminal as fast as
you can) to read the Claude Code error. Most common cause: Claude Code
not signed in, plugin install failure, vault path wrong.

## Bot stopped replying

**Symptom.** Telegram messages to the bot get no response. Session is
alive (`health-check.sh` exits 0).

**Diagnosis.** Pairing dropped, token rotated, or Channels plugin
unloaded.

**Fix.**

1. `tmux attach -t "$TMUX_SESSION"` and look for errors in the pane.
2. If you see `not authenticated` or `pairing` errors → re-pair (see
   [operations.md](operations.md#re-pair-the-bot)).
3. If you see no plugin output at all → `/plugin install channels` then
   `/telegram:configure` and re-pair.
4. If the token was rotated, update the 1Password item, then restart
   the service.

## 1Password CLI locked at startup

**Symptom.** `start-jarvis.sh` exits with `1Password CLI is not signed
in. Run: op signin`.

**Fix.**

```bash
op signin
systemctl --user restart jarvis-router
```

Make `op` sign-in persistent (e.g. via the 1Password desktop app
integration, or a long-lived session token) if this is a recurring
problem.

## Vault unmounted / Syncthing conflict on `routing-memory.md`

**Symptom.** Jarvis reports it can't read personas or write the routing
log. Or you see `routing-memory.md.sync-conflict-*.md` in the project
folder.

**Fix (unmounted).**

1. Remount the vault, then restart: `systemctl --user restart jarvis-router`.

**Fix (Syncthing conflict).**

1. `cd "${VAULT_PATH}/10 Projects/Jarvis"`
2. Diff the conflict file against `routing-memory.md`
3. Manually merge entries (the file is append-only, so this is usually
   easy — keep the union of entries from both files)
4. Delete the `.sync-conflict-*.md`
5. Let Syncthing re-converge

## Today's routing log file missing

**Symptom.** `health-check.sh` notes
`today's routing log not yet created`.

**Diagnosis.** Either Jarvis has handled zero requests today (normal
overnight), or Jarvis has handled requests but failed to write the
log (look for permission errors on `00 Inbox/`).

**Fix.** Send a test message from Telegram. If the file appears, the
warning was just because it was a slow morning. If it doesn't appear,
check `ls -ld "${VAULT_PATH}/00 Inbox/"` for write permission for the
user running the service.

## Channels plugin not loaded after restart

**Symptom.** `tmux attach` shows Claude Code is up but `/plugin list`
doesn't include Channels.

**Fix.** Inside the session: `/plugin install channels` then restart
Claude Code (`exit` or `Ctrl-D`, systemd brings it back), then re-pair
the bot.

## Multiple Jarvis sessions accidentally running

**Symptom.** `tmux ls` shows two sessions with names like `jarvis` and
`jarvis-1`. Bot responds intermittently or with conflicting personas.

**Fix.**

```bash
systemctl --user stop jarvis-router
bash scripts/stop-jarvis.sh
tmux kill-session -t jarvis-1 2>/dev/null || true
# Verify clean state
tmux ls
systemctl --user start jarvis-router
```

## Need to debug live behavior

The cheapest way to see what Jarvis is doing right now:

```bash
tmux attach -t "$TMUX_SESSION"   # Ctrl-b d to detach when done
```

You can read the prompt history in the pane. If you want to scroll back
further, enter copy mode (`Ctrl-b [`) and `Page-Up`. `q` exits copy mode.
