# jarvis-router

Bootstrap and supervisor scripts for **Jarvis**, Andrew's headless
Claude Code router. Jarvis runs in a `tmux` session, pairs to a Telegram
bot via Anthropic's **Channels** plugin, and dispatches incoming
messages to one of four personas (Kai, Forge, Marcus Webb, raw operator).

This repo does **not** contain Jarvis's brain. The routing identity,
personas, memory, and logs all live in Andrew's Obsidian vault. This
repo's only job is to start the process, supervise it, and document the
contract.

---

## What this repo is (and isn't)

| Lives here                          | Lives in the vault                              |
|-------------------------------------|--------------------------------------------------|
| `scripts/start-jarvis.sh`           | `10 Projects/Jarvis/CLAUDE.md` (routing identity)|
| `scripts/stop-jarvis.sh`            | `80 Personas/{Kai,Forge,Marcus Webb}*.md`        |
| `scripts/health-check.sh`           | `10 Projects/Jarvis/routing-memory.md`           |
| `scripts/init-vault-scaffold.sh`    | `00 Inbox/jarvis-routing-YYYY-MM-DD.md`          |
| `systemd/jarvis-router.service`     |                                                  |
| `docs/`                             |                                                  |

If this repo is deleted and the vault is intact, Jarvis can be rebuilt
by hand in under an hour using [docs/setup.md](docs/setup.md).

---

## Prerequisites

- `tmux` ≥ 3.0
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and signed in
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) signed in
- The Obsidian vault present at `VAULT_PATH` (see `.env.example`)
- Linux with user-level `systemd` (for autostart)

For tests and lint:

- `bats-core` (`bats` on PATH)
- `shellcheck`

---

## First-time setup

The detailed runbook is in [docs/setup.md](docs/setup.md). The summary:

1. Create the bot in Telegram via `@BotFather` and store the token in
   1Password. See the vault doc `2026-05-17 - Telegram Bot Setup for
   Jarvis - Steps.md` for the per-screen flow.
2. Clone this repo. `cp .env.example .env`, fill in `VAULT_PATH` and
   `OP_BOT_TOKEN_REF`.
3. `bash scripts/init-vault-scaffold.sh` — seeds `routing-memory.md`
   and verifies the personas + routing identity exist.
4. `bash scripts/start-jarvis.sh` — brings up tmux + Claude Code +
   Channels.
5. Pair the bot: send any message to the bot in Telegram, copy the
   6-character code Claude Code prints, paste it back in the Telegram
   DM.
6. Send `morning. what should I tackle first today` — you should get a
   reply in Kai's voice.

---

## Daily operations

```bash
bash scripts/start-jarvis.sh    # idempotent
bash scripts/stop-jarvis.sh     # idempotent
bash scripts/health-check.sh    # one-line status, exit code matters
tmux attach -t "$TMUX_SESSION"  # then Ctrl-b d to detach (do NOT Ctrl-c)
```

Full ops reference: [docs/operations.md](docs/operations.md).

---

## Autostart

```bash
mkdir -p ~/.config/systemd/user
cp systemd/jarvis-router.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now jarvis-router
loginctl enable-linger "$USER"     # survives logout
```

---

## Recovery

If something is wrong, [docs/runbook.md](docs/runbook.md) is the
incident playbook (dead session, unpaired bot, locked 1Password,
vault unmounted, etc.).

---

## Testing and lint

```bash
bash scripts/test.sh    # runs shellcheck + bats
```

Test strategy and per-suite descriptions: [docs/testing.md](docs/testing.md).

---

## Where things live

| Concept                 | Path                                                          |
|-------------------------|---------------------------------------------------------------|
| Routing identity        | `${VAULT_PATH}/10 Projects/Jarvis/CLAUDE.md`                  |
| Personas                | `${VAULT_PATH}/80 Personas/`                                  |
| Routing memory          | `${VAULT_PATH}/10 Projects/Jarvis/routing-memory.md`          |
| Daily routing log       | `${VAULT_PATH}/00 Inbox/jarvis-routing-YYYY-MM-DD.md`         |
| Bot token (1Password)   | `op://Jarvis/jarvis-router-bot/bot_token`                     |
| Working dir for `claude`| `${VAULT_PATH}/10 Projects/Jarvis/`                           |

See [docs/vault-contract.md](docs/vault-contract.md) for the full
contract on each vault file Jarvis touches.
