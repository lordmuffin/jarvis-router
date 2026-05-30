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

---

## Forge Agent

Forge runs as a second, on-demand Claude Code session driven by a
queue file in the vault.

**How Kai triggers Forge**: Kai writes a task under `## Active` in
`${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/forge-queue.md`. The
`forge-watcher.service` notices the change via `inotifywait` and runs
`scripts/start-forge.sh`, which launches Claude Code in a tmux session
named `forge` using the ForgeBot Telegram identity.

**Manual control**:

```bash
bash scripts/start-forge.sh         # start (idempotent)
tmux attach -t forge                # observe
tmux kill-session -t forge          # hard stop
bash scripts/health-check.sh        # see forge status under === Workloads ===
journalctl --user -u forge-watcher -f
```

If Forge crashes during a task, `start-forge.sh` writes a `## Paused`
section into `forge-queue.md` and DMs Andrew via ForgeBot. Reply
`resume` or `skip` in the Kai chat and Kai will handle re-queuing.

---

## Workload Management

The unified entry point for all on-demand workloads (forge,
transcription, voice). Use these instead of starting individual
session scripts directly.

```bash
bash scripts/workload-start.sh forge                  # local resolution
bash scripts/workload-start.sh transcription          # local
bash scripts/workload-start.sh voice                  # LXC 400
bash scripts/workload-start.sh forge --cloud          # force Vast.ai
bash scripts/workload-stop.sh forge                   # tear down (local + cloud)
```

**Resolution order inside `workload-start.sh`**:

1. Local tmux session already running → no-op, log entry
2. `--cloud` flag set OR another workload already holds the GPU → Vast.ai
3. Gaming PC reachable AND `k3s-agent` inactive (gaming mode) → SSH to
   gaming PC and bring up Ollama
4. Fallback: local tmux launch via `start-<type>.sh`

**How Kai triggers workloads** (vault wiring, not in this repo): the
vault `10 Projects/Jarvis/CLAUDE.md` routing rules call
`scripts/classifier.sh "<incoming-message>"` as step 1. If exit 0,
Kai calls `scripts/workload-start.sh <type>` directly and skips LLM
routing. Anything ambiguous falls through to Sonnet for full LLM
routing.

**Cost guardrail (Vast.ai)**: cloud GPU is for batch jobs **> 30
minutes** only — never for interactive sessions. Cloud instances burn
money the second they're rentable. Always run
`bash scripts/workload-stop.sh <type>` when done; verify with
`bash scripts/vast-launcher.sh status <type>`.

**Gaming PC inference**: the gaming PC (RX 9070 XT 16GB, CachyOS, ROCm
6.3+) hosts Ollama. "Gaming mode" is detected by SSH-checking that
`systemctl is-active k3s-agent` returns `inactive` — when Andrew is
gaming, k3s-agent is stopped and the GPU is free. The 16GB VRAM ceiling
means 70B models **will not fit** — defaults in `.env.example` use
`qwen2.5-coder:14b` (~9GB Q4) for code/forge, `llama3.1:8b-q8` for
general, and `qwen2.5:3b` for classification.

**Voice stack**: lives inside LXC 400 on the Proxmox host
(`192.168.1.101`). `start-voice.sh` uses `pct exec 400` (via SSH to
Proxmox) to drive `docker compose start/stop` and polls the Kokoro
(`:8880`) and XTTS (`:8881`) health endpoints.

