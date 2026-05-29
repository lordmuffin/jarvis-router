# Vault contract

Jarvis treats specific paths inside the Obsidian vault as load-bearing.
This document is the single source of truth for what each file is, who
writes it, and what happens if it's missing or malformed.

## `10 Projects/Jarvis/CLAUDE.md`

The Jarvis routing identity — the system prompt that defines you-as-the-router.

- **Created by.** Andrew, by hand.
- **Read by.** Claude Code at startup (auto-loaded because
  `start-jarvis.sh` `cd`s into `10 Projects/Jarvis/` before invoking
  `claude`).
- **Written by.** Nothing automated. Andrew edits when he wants to
  change routing behavior.
- **Format.** Freeform markdown. The current content is the routing
  brief: mission, runtime context, persona table, routing logic, slash
  override behavior, learning rules, logging rules, non-negotiables,
  examples.
- **Missing.** Jarvis starts without an identity. `init-vault-scaffold.sh`
  warns; `start-jarvis.sh` warns. Behavior degrades to "generic Claude
  Code session" — won't route, won't log, won't act as a persona switch.

## `10 Projects/Jarvis/routing-memory.md`

Append-only learned-pattern log.

- **Created by.** `scripts/init-vault-scaffold.sh` (one time, with
  frontmatter and an "Entry format" section).
- **Read by.** Jarvis at runtime, before every routing decision.
- **Written by.** Jarvis at runtime, when it observes a correction or a
  durable new pattern.
- **Format.** YAML frontmatter (`type: routing-memory`, `tags`, `created`),
  prose explaining the entry format, then one entry per line:

  ```
  [YYYY-MM-DD] pattern: "<phrase>" -> persona: <Kai|Forge|Marcus|operator> (confidence: low|med|high) -- note: <why>
  ```

- **Append-only?** Yes. Jarvis never edits or removes prior entries.
  Andrew can prune by hand if entries get noisy.
- **Atomically written?** No — short appends are atomic enough on local
  filesystems for the volume involved. Syncthing-induced conflicts are
  the failure mode to watch (see runbook).
- **Missing.** `init-vault-scaffold.sh` recreates it. Jarvis falls back
  to pure heuristic routing until it exists.

## `00 Inbox/jarvis-routing-YYYY-MM-DD.md`

Daily per-decision audit log.

- **Created by.** Jarvis at runtime, on first decision of each day.
- **Read by.** Andrew (manually), `/operator` queries inside Jarvis
  (e.g. "who have I been routing to most this week").
- **Written by.** Jarvis at runtime, one line per decision.
- **Format.** Freeform markdown, but the canonical line format from
  the system prompt is:

  ```
  HH:MM | "<first 60 chars of message>..." -> <persona> | <auto|override|default> | <one-line reason>
  ```

- **Append-only?** Yes.
- **Missing.** Jarvis creates today's file on the next decision. Past
  days' files cannot be reconstructed — once they're gone, the audit
  trail for that day is gone.

## `80 Personas/Kai - The Kaizen Engineer.md`

## `80 Personas/Forge - The Platform Engineer.md`

## `80 Personas/Marcus Webb - Platform Product Manager.md`

Persona definition files. The text Jarvis loads into context when
adopting a persona.

- **Created by.** Andrew, by hand.
- **Read by.** Jarvis at runtime, on a routing decision that selects
  that persona.
- **Written by.** Nothing automated.
- **Format.** YAML frontmatter + sections (Identity, Core Values, Voice
  & Tone, etc.). The structure is consistent across the three but not
  strictly enforced — Jarvis adapts.
- **Missing.** `init-vault-scaffold.sh` exits non-zero. Jarvis cannot
  route to a missing persona.

## Filename tolerance

`init-vault-scaffold.sh` uses globs (`Kai*.md`, `Forge*.md`,
`Marcus*Webb*.md`) when checking persona presence so small filename
edits don't break the scaffold check. Jarvis itself reads whatever it
finds at the path declared in the routing identity — keep the routing
identity's persona table in sync with the actual filenames if you
rename.

## Dirs Jarvis assumes exist

- `${VAULT_PATH}`
- `${VAULT_PATH}/10 Projects/Jarvis/`
- `${VAULT_PATH}/80 Personas/`
- `${VAULT_PATH}/00 Inbox/`

`init-vault-scaffold.sh` validates all four and fails non-zero if any
are missing.
