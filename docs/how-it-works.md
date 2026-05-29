# How it works

Each script in execution order. Inputs, outputs, failure modes,
idempotency.

## `scripts/lib/common.sh`

Sourced by every other script. Provides:

- `log` / `warn` / `err` / `die` — leveled stderr logging
- `load_env` — reads `${JARVIS_ENV_FILE:-${REPO_ROOT}/.env}`, sets
  defaults, requires `VAULT_PATH` and `TMUX_SESSION`
- `op_read <ref>` — resolves a 1Password secret reference, fails loudly
  if `op` is missing or not signed in
- `tmux_session_alive <name>` — wraps `tmux has-session`
- `todays_routing_log` — prints the absolute path to today's routing log

Tests override `JARVIS_ENV_FILE` to point at a sandbox.

## `scripts/init-vault-scaffold.sh`

**Purpose.** Make sure the vault has every file Jarvis expects to
read or write at runtime.

**Inputs.** `.env` (via `load_env`).

**Outputs.**
- Creates `${JARVIS_PROJECT_DIR}/routing-memory.md` with a usable header
  if absent.
- Prints a three-section summary (present / created / missing).
- Exit codes: `0` if all required pieces are present or were created,
  non-zero if a persona file is missing or the vault path doesn't exist.

**Will NOT create.** `${JARVIS_PROJECT_DIR}/CLAUDE.md` (the routing
identity) — that's Andrew's content. Reports it as missing instead.

**Idempotency.** Safe to run any number of times. The header check on
`routing-memory.md` looks for file existence only — it does not
overwrite or merge.

## `scripts/start-jarvis.sh`

**Purpose.** Bring up the tmux session that runs Claude Code with the
Channels plugin.

**Inputs.** `.env`, working `tmux` and `claude` on `PATH`, optional
`op` (only invoked if `OP_BOT_TOKEN_REF` is non-empty).

**Outputs.**
- A live tmux session named `$TMUX_SESSION` running `claude` with CWD
  `$JARVIS_PROJECT_DIR` (so `CLAUDE.md` is auto-loaded as the routing
  identity).
- Stdout: instructions for the first-time pairing flow.
- Exit codes: `0` on success or "already running", non-zero on any
  failure.

**Failure modes (each fails fast with a useful message).**
- `tmux` or `claude` not on PATH → die
- `JARVIS_PROJECT_DIR` doesn't exist → die
- `op` not signed in → die (only when `OP_BOT_TOKEN_REF` is set)
- tmux session dies during startup → die

**Idempotency.** If `$TMUX_SESSION` already exists, exits 0 without
touching it. Safe under systemd `Restart=on-failure`.

**Note.** The script does NOT install the Channels plugin or run
`/telegram:configure` for you — those are one-time setup steps the
human runs once after the first start. The script tells you to do this
in its output.

## `scripts/health-check.sh`

**Purpose.** One-line status + meaningful exit code.

**Inputs.** `.env`, live `tmux`.

**Outputs.**
- Stderr: one line of status.
- Exit codes:
  - `0` — `ok`: session exists and pane shows no obvious error markers
  - `1` — `degraded`: session exists but pane shows
    `error|exception|not authenticated|pairing failed`
  - `2` — `dead`: session does not exist

**Soft warnings (don't change exit code).** If it's past 9am local and
today's `jarvis-routing-<date>.md` doesn't exist yet, mention it.

**Used by.** `systemd` (`ExecStartPost`) and Andrew (manual).

## `scripts/stop-jarvis.sh`

**Purpose.** Tear down the session gracefully, kill as fallback.

**Inputs.** `.env`, live `tmux`.

**Outputs.**
- Stderr: status messages.
- Exit codes: `0` on success or "already stopped", non-zero if `tmux
  kill-session` fails.

**Behavior.**
1. If session doesn't exist → exit 0.
2. Send `/exit` + Enter to the Claude Code prompt.
3. Wait up to 10 seconds for the session to die.
4. If still alive → `tmux kill-session`.

**Idempotency.** Safe to run any number of times.

## `scripts/test.sh`

**Purpose.** Lint + test wrapper. Run before every commit.

**Inputs.** None.

**Outputs.**
- `shellcheck` over `scripts/**/*.sh`
- `bats tests/`
- Exit codes: forwards the first failure.

**Skips.** Either tool with a warning if not on PATH. `bats` missing is
a hard failure (we want it on dev hosts).
