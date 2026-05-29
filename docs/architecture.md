# Architecture

## One picture

```
┌─────────────┐    HTTPS poll    ┌──────────────────────┐
│  Telegram   │ ◄──────────────► │  Channels plugin     │
│  bot DM     │                  │  (inside Claude Code)│
└─────────────┘                  └──────────┬───────────┘
                                            │
                                            ▼
                                 ┌──────────────────────┐
                                 │  Claude Code session │
                                 │  (system prompt =    │
                                 │  vault CLAUDE.md =   │
                                 │  Jarvis routing      │
                                 │  identity)           │
                                 └──────────┬───────────┘
                                            │ reads/writes
                                            ▼
                                 ┌──────────────────────┐
                                 │  Obsidian vault      │
                                 │  - 80 Personas/      │
                                 │  - 10 Projects/      │
                                 │    Jarvis/           │
                                 │      CLAUDE.md       │
                                 │      routing-memory  │
                                 │  - 00 Inbox/         │
                                 │    jarvis-routing-*  │
                                 └──────────────────────┘

  Supervised by ▲
  ┌───────────────────────────────┐
  │ tmux session ("$TMUX_SESSION")│
  └───────────────┬───────────────┘
                  │
  ┌───────────────▼───────────────┐
  │ systemd --user                │
  │ jarvis-router.service         │
  └───────────────────────────────┘

  Bot token resolved from 1Password at start, never written to disk.
```

## Who owns what

| Thing                          | Owner            | Lives in                              |
|--------------------------------|------------------|---------------------------------------|
| Routing brain                  | Andrew (vault)   | `10 Projects/Jarvis/CLAUDE.md`        |
| Personas                       | Andrew (vault)   | `80 Personas/`                        |
| Learned routing patterns       | Jarvis (runtime) | `10 Projects/Jarvis/routing-memory.md`|
| Per-decision audit log         | Jarvis (runtime) | `00 Inbox/jarvis-routing-<date>.md`   |
| Telegram bot token             | 1Password        | `op://Jarvis/jarvis-router-bot/...`   |
| Process supervision            | this repo        | `systemd/jarvis-router.service`       |
| Start/stop/health              | this repo        | `scripts/`                            |

## Why Path A (Channels) for v0

Per Andrew's scope choice. Channels couples Telegram to one Claude Code
session via a 6-char pairing code in ~2 minutes. No bot code to write,
maintain, or rotate. The trade-off — no inline action buttons, no
programmatic `sendMessage` from outside the session — is acceptable for
v0 because Jarvis is purely conversational. Programmatic dispatch
(Path B, raw bot API) becomes a separate component later if and when
the system grows HITL approve/reject flows.

## Why everything is in the vault

The vault is already version-controlled (Syncthing + git per the May 8
"Open Decisions" working session). The routing identity, personas, and
memory are all just markdown — they belong with the rest of Andrew's
second brain. This repo deliberately holds no behavior. If the
supervisor host dies, Andrew restores the vault from any other device
and stands up a new supervisor with the runbook in
[setup.md](setup.md).

## Failure isolation

| Failure                | Visible symptom                       | Caught by                       |
|------------------------|---------------------------------------|---------------------------------|
| Telegram down          | Bot stops replying                    | Andrew (manually)               |
| Channels plugin crash  | Bot pairs but no response             | Andrew via `tmux attach`        |
| Claude Code OOM        | tmux session has dead pane            | `health-check.sh` (degraded)    |
| tmux session killed    | Session gone                          | `health-check.sh` (dead)        |
| systemd restart loop   | Repeated start attempts in journal    | `journalctl --user -u jarvis-router` |
| 1Password locked       | `start-jarvis.sh` fails before tmux   | `start-jarvis.sh` exit code     |
| Vault unmounted        | Jarvis cannot Read personas or log    | Read errors inside session      |
| Syncthing conflict     | `routing-memory.md.sync-conflict-*`   | Manual periodic check           |
