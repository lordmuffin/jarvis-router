# jarvis-router (this repo)

This repo is the **dispatch and supervision layer** for Jarvis. It owns
two things and only two things:

1. **Process lifecycle** — starting, stopping, and health-checking the
   tmux sessions that run Claude Code (Kai router, Forge agent,
   transcription worker, voice stack supervisor).
2. **Workload dispatch** — deciding where a workload runs (local tmux,
   gaming-PC GPU via SSH, or Vast.ai cloud) and a thin rule-based
   classifier that short-circuits the LLM call for unambiguous intents
   (forge build, transcribe audio, start voice).

What does NOT live here:

- **Routing decisions, personas, system prompts, memory.** All of that
  lives in Andrew's Obsidian vault at `/home/lordmuffin/Documents/Notes/`:
  - Routing identity → `10 Projects/Jarvis/CLAUDE.md`
  - Personas → `80 Personas/`
  - Routing memory → `10 Projects/Jarvis/routing-memory.md`
  - Routing logs → `00 Inbox/jarvis-routing-YYYY-MM-DD.md`
  - Forge queue → `10 Projects/Jarvis/Infrastructure/forge-queue.md`
  - Transcription queue → `10 Projects/Jarvis/Infrastructure/transcription-queue.md`

- **The Channels plugin source.** Telegram I/O happens inside the Kai
  Claude Code session via the runtime `channels` plugin. This repo
  cannot hook the message handler directly — `classifier.sh` is exposed
  as a CLI that the vault's CLAUDE.md routing rules invoke as step 1.

**If you want to change Jarvis's behavior, voice, or routing rules,
edit the vault.** This repo changes when you need to add or modify a
workload type, its dispatch logic, or a process supervisor.

See [README.md](README.md) for the install runbook and the
[docs/](docs/) folder for operations, setup, and the runbook.
