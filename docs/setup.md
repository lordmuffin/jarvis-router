# Setup

First-time install, end-to-end. Read the [README](../README.md) first
for the one-page overview; this doc is the detailed walk-through.

## 1. Dependencies

| Tool          | Purpose                                | How to verify             |
|---------------|----------------------------------------|---------------------------|
| `tmux` ≥ 3.0  | Headless session that owns Claude Code | `tmux -V`                 |
| Claude Code   | The Jarvis runtime                     | `claude --version`        |
| `op` (1Password CLI) | Bot token retrieval at start    | `op --version && op whoami` |
| `bats-core`   | Test runner (tests only)               | `bats --version`          |
| `shellcheck`  | Bash lint (build only)                 | `shellcheck --version`    |

If any of `tmux`, `claude`, or `op` is missing, install before going
further. `bats` and `shellcheck` are only needed if you plan to run the
test suite.

## 2. Vault prerequisites

The vault is the source of truth. Confirm:

- `VAULT_PATH` (default `/home/lordmuffin/Documents/Notes`) exists
- `VAULT_PATH/80 Personas/` contains:
  - `Kai - The Kaizen Engineer.md`
  - `Forge - The Platform Engineer.md`
  - `Marcus Webb - Platform Product Manager.md`
- `VAULT_PATH/00 Inbox/` exists and is writable
- `VAULT_PATH/10 Projects/Jarvis/CLAUDE.md` exists and contains the
  Jarvis routing identity (the system prompt that defines you-as-router)

`scripts/init-vault-scaffold.sh` reports on each of the above and is
safe to re-run at any time.

## 3. BotFather flow

Defer to the vault doc:

> `10 Projects/Jarvis/2026-05-17 - Telegram Bot Setup for Jarvis - Steps.md`

Summary:

1. Telegram → `@BotFather` → `/newbot`
2. Display name: `Jarvis` (or whatever)
3. Username: must end in `bot` (e.g. `apj_jarvis_bot`)
4. Save the API token straight into 1Password (do NOT paste anywhere
   else). The vault doc has the exact item shape.

## 4. 1Password setup

- Vault: `Jarvis`
- Item: `jarvis-router-bot` (type: API Credential)
- Fields: `bot_username`, `bot_token`, `bot_id`, `created`
- Secret reference for `.env`: `op://Jarvis/jarvis-router-bot/bot_token`

Verify the reference resolves:

```bash
op signin
op read "op://Jarvis/jarvis-router-bot/bot_token" >/dev/null && echo OK
```

## 5. Repo install

```bash
git clone <repo-url> ~/git/jarvis-router
cd ~/git/jarvis-router
cp .env.example .env
$EDITOR .env    # fill in VAULT_PATH, TMUX_SESSION, OP_BOT_TOKEN_REF
bash scripts/init-vault-scaffold.sh
```

If `init-vault-scaffold.sh` exits non-zero, fix what it reports before
moving on.

## 6. First start

```bash
bash scripts/start-jarvis.sh
tmux attach -t "$TMUX_SESSION"
```

Inside the attached session (first-run only):

1. `/plugin install channels`
2. `/telegram:configure` → paste the bot token from 1Password
3. Restart Claude Code (the plugin requires a restart to start polling)
4. Detach with `Ctrl-b d` — **never `Ctrl-c`** (that kills the session)

Pair the bot:

5. Open the Telegram DM with the bot and send any message
6. Claude Code prints a 6-character pairing code in the terminal
7. Paste the code into the Telegram DM
8. You should see `Paired. Say hi to Claude.`

Smoke test:

9. From Telegram: `morning. what should I tackle first today`
10. Expect a reply in Kai's voice plus a new entry in
    `${VAULT_PATH}/00 Inbox/jarvis-routing-<today>.md`

## 7. Autostart

```bash
mkdir -p ~/.config/systemd/user
cp systemd/jarvis-router.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now jarvis-router
loginctl enable-linger "$USER"
```

Verify:

```bash
systemctl --user status jarvis-router
bash scripts/health-check.sh
```

## 8. Forge agent (optional)

Forge is a second, on-demand work session. Kai delegates background
implementation tasks to it via a queue file in the vault. Skip this
section if you only want Kai.

### 8a. Create the ForgeBot

1. Open Telegram → BotFather → `/newbot`. Name it (e.g. "Jarvis
   ForgeBot"). Pick a username ending in `bot`.
2. Copy the token BotFather hands back.

### 8b. Store the token in 1Password

```bash
op item create --category=login \
  --vault=Jarvis \
  --title='jarvis-router-forgebot' \
  bot_token='<paste-token>'
```

(Vault/item/field names follow the same convention as the Kai bot.
Confirm the exact reference works with `op read`.)

### 8c. Configure the watcher

```bash
# In .env (or .env.local), set:
FORGE_OP_BOT_TOKEN_REF="op://Jarvis/jarvis-router-forgebot/bot_token"

# Make sure the queue file exists in the vault:
mkdir -p "${VAULT_PATH}/10 Projects/Jarvis/Infrastructure"
touch    "${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md"

# Install the systemd units alongside jarvis-router:
cp systemd/forge-watcher.service ~/.config/systemd/user/
cp systemd/forge-session.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now forge-watcher.service
```

Optionally install `inotify-tools` for event-driven wakeups (the
watcher falls back to a 30-second poll loop without it):

```bash
sudo apt install inotify-tools     # Debian/Ubuntu
```

### 8d. Verify

```bash
systemctl --user status forge-watcher
bash scripts/health-check.sh
# expect: forge: idle | forge-watcher: active
```

Smoke test:

```bash
echo '- [ ] hello forge' >> \
  "${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md"
# Within ~30s a Forge tmux session appears: tmux ls
# /tmp/forge-start.log gets a "RUNNING" line
```

## 9. Uninstall

```bash
systemctl --user disable --now jarvis-router
systemctl --user disable --now forge-watcher 2>/dev/null || true
bash scripts/stop-jarvis.sh
tmux kill-session -t forge 2>/dev/null || true
rm -rf ~/git/jarvis-router
```

The vault state survives — `routing-memory.md`, daily logs, personas,
the Forge queue, and the routing identity are all preserved by design.
