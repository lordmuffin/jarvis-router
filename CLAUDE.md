# jarvis-router (this repo)

This repo is **bootstrap scripts only**. It stands up and supervises the
headless Claude Code session that runs Jarvis. It contains no routing
logic, no persona definitions, no system prompt, and no memory files.

All of those live in Andrew's Obsidian vault at
`/home/lordmuffin/Documents/Notes/`:

- Routing identity → `10 Projects/Jarvis/CLAUDE.md`
- Personas → `80 Personas/`
- Routing memory → `10 Projects/Jarvis/routing-memory.md`
- Routing logs → `00 Inbox/jarvis-routing-YYYY-MM-DD.md`

**If you're here to change Jarvis's behavior, voice, or routing rules,
edit the vault — not this repo.** This repo only changes when you need
to adjust how the process starts, stops, or is monitored.

See [README.md](README.md) for the install and ops runbook, and the
[docs/](docs/) folder for everything else.
