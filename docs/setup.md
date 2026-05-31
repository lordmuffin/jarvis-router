# Setup

First-time install, end-to-end. Read the [README](../README.md) first
for the one-page overview; this doc is the detailed walk-through.

## 1. Dependencies

| Tool          | Purpose                                | How to verify             |
|---------------|----------------------------------------|---------------------------|
| `tmux` ≥ 3.0  | Headless session that owns Claude Code | `tmux -V`                 |
| Claude Code   | The Jarvis runtime                     | `claude --version`        |
| `bun`         | Runtime the Telegram channel plugin spawns its MCP server with | `bun --version` |
| `op` (1Password CLI) | Bot token retrieval at start    | `op --version && op whoami` |
| `bats-core`   | Test runner (tests only)               | `bats --version`          |
| `shellcheck`  | Bash lint (build only)                 | `shellcheck --version`    |

If any of `tmux`, `claude`, `bun`, or `op` is missing, install before
going further. `bats` and `shellcheck` are only needed if you plan to
run the test suite.

Install `bun` if absent: `curl -fsSL https://bun.sh/install | bash`
(then re-source your shell so `~/.bun/bin/bun` is on PATH). Without
`bun`, the Telegram channel plugin loads but its MCP server fails to
spawn (ENOENT) and the bot never comes online — `start-jarvis.sh`
preflights this and fails early.

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

`start-jarvis.sh` resolves `OP_BOT_TOKEN_REF` via `op read` and writes
the plain token to `~/.claude/channels/telegram/.env` (mode 0600, single
`TELEGRAM_BOT_TOKEN=` line) every time it runs. The Channels plugin's
MCP server reads that file at boot — its `.env` parser is a literal
regex and does NOT expand `$(...)`, `op read`, or `op://` references,
so the script does the resolution itself. Side effect: `/telegram:configure`
inside the session is no longer required for the token to be present;
it's only useful if you want to bypass 1Password.

Detach with `Ctrl-b d` — **never `Ctrl-c`** (that kills the session).

**Tokens are per-host** — Telegram pairings live in
`~/.claude/channels/telegram/approved/` and don't carry across machines.
Each new host pairs fresh.

Pair the bot:

1. Open the Telegram DM with the bot and send any message
2. Claude Code prints a 6-character pairing code in the terminal
3. Paste the code into the Telegram DM
4. You should see `Paired. Say hi to Claude.`

Smoke test:

5. From Telegram: `morning. what should I tackle first today`
6. Expect a reply in Kai's voice plus a new entry in
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

## 8. Forge Agent setup (optional but recommended)

Forge runs on demand when Kai writes a task to `forge-queue.md`.

1. **Create a second Telegram bot** via `@BotFather` → `/newbot`.
   Display name: `Forge` (or `JarvisForge`). Username must end in `bot`.
2. **Store the token in 1Password**:

   ```bash
   op item create --category login --title "Jarvis ForgeBot" \
       --vault Personal token=<paste-token>
   ```

3. **Add the secret reference to `.env`**:

   ```bash
   FORGE_OP_BOT_TOKEN_REF="op://Personal/Jarvis ForgeBot/token"
   ```

4. **Install inotify-tools** (for event-driven queue watching; falls
   back to a 30s poll loop if missing):

   ```bash
   # Arch / CachyOS:
   sudo pacman -S inotify-tools
   ```

5. **Enable the watcher** under systemd --user:

   ```bash
   cp systemd/forge-watcher.service systemd/forge-session.service \
       ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now forge-watcher.service
   systemctl --user status forge-watcher
   ```

6. **Smoke test**: append a dummy task to the Active section of the
   queue and confirm Forge starts within 30s:

   ```bash
   echo '- [ ] test task — delete me' \
       >> "${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md"
   # Wait up to 30s, then:
   tmux has-session -t forge && echo "Forge launched"
   ```

## 9. Workload prerequisites (optional)

These are needed only if you plan to use `workload-start.sh` for
transcription, voice, or cloud GPU.

### Vast.ai cloud GPU

```bash
# 1. Get an API key from https://vast.ai/console → Account → API Key
# 2. Add to .env:
VAST_API_KEY=<your-key>
# 3. Verify search works (no charge to search):
bash scripts/vast-launcher.sh status forge   # exits 0 with "no instance"
```

**Cost guardrail**: only use cloud GPU for batch jobs > 30 min. Always
verify the destroy succeeded — `vast.ai/console` shows live instances.

### Gaming PC (Ollama with AMD ROCm)

One-time setup on the gaming PC (confirmed: AMD Radeon RX 9070 XT 16GB,
gfx1201/RDNA 4, CachyOS 7.0.6 with DRM 3.64):

```bash
# 1. On the gaming PC: install Ollama with ROCm.
yay -S ollama-rocm        # requires ROCm 6.3+ for native gfx1201

# 2. If ROCm doesn't detect gfx1201, set the override:
echo 'export HSA_OVERRIDE_GFX_VERSION=11.0.0' >> ~/.config/fish/config.fish

# 3. Pre-pull the default model:
ollama pull qwen2.5-coder:14b     # ~9GB Q4

# 4. On the Jarvis host: set up SSH key auth to the gaming PC:
ssh-copy-id -i ~/.ssh/id_ed25519.pub gaming-pc-host
# Add to .env:
#   GAMING_PC_HOST=<ip-or-hostname>
#   GAMING_PC_SSH_KEY=~/.ssh/id_ed25519
#   GAMING_PC_INFERENCE_MODEL=qwen2.5-coder:14b

# 5. Verify:
bash scripts/gaming-pc-launcher.sh available    # 0 if reachable + k3s-agent inactive
bash scripts/gaming-pc-launcher.sh status       # 0 if ollama serve is up
```

**16GB VRAM ceiling**: 70B models will **not fit**. Stick to:
`qwen2.5-coder:14b` (forge/code), `llama3.1:8b-q8` (general),
`qwen2.5:3b` (classification only).

### Voice stack (LXC 400)

The Kokoro TTS + XTTS docker stack runs inside LXC 400 on the Proxmox
host (`192.168.1.101`). Andrew sets up the LXC and docker-compose file
out of band; `start-voice.sh` only needs SSH access to Proxmox to call
`pct exec 400`. Confirm:

```bash
ssh 192.168.1.101 "pct exec 400 -- docker ps"   # should list voice containers
bash scripts/start-voice.sh status               # 0 if both endpoints green
```

## 10. Uninstall

```bash
systemctl --user disable --now jarvis-router forge-watcher
bash scripts/workload-stop.sh forge
bash scripts/workload-stop.sh transcription
bash scripts/workload-stop.sh voice
bash scripts/stop-jarvis.sh
rm -rf ~/git/jarvis-router
```

The vault state survives — `routing-memory.md`, daily logs, personas,
the routing identity, the forge queue, and the transcription queue
are all preserved by design.
