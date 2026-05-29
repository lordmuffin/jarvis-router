# Testing

## What we test

The scripts' contracts:

- **Exit codes.** Each script has documented exit semantics — health-check
  returns 0/1/2 for ok/degraded/dead, start/stop are idempotent (always
  0 in the no-op case), init-vault-scaffold is non-zero only when the
  vault is unusable.
- **File creation.** `init-vault-scaffold.sh` creates the routing memory
  file with the expected header, and does NOT create `CLAUDE.md`.
- **Idempotency.** Repeat invocations don't corrupt state.
- **Fail-fast paths.** Missing personas, missing vault, missing
  `JARVIS_PROJECT_DIR` all fail with non-zero exit and a useful message.

## What we do NOT test here

Jarvis's routing decisions, persona voice, learning behavior, and
destructive-action confirmation are LLM behaviors. They're validated by
the manual smoke tests in the [README](../README.md#first-time-setup)
and in the plan file's verification section. There's no automated way
to assert "Kai replied in Kai's voice" without paying for an LLM call,
and the cost/value trade is wrong for a bootstrap repo this small.

## Tooling

- [bats-core](https://bats-core.readthedocs.io/) — bash test runner
- [shellcheck](https://www.shellcheck.net/) — bash linter
- `mktemp -d` — per-test sandbox vaults under `tests/.tmp/`
- tmux session names prefixed `jarvis-router-test-<pid>` to avoid
  collision with the user's real session

## Run

```bash
bats tests/                                  # all suites
bats tests/test-health-check.bats            # one suite
bash scripts/test.sh                         # shellcheck + bats
```

Tests do not need network access, 1Password sign-in, or a running
Claude Code instance. The start-stop suite stubs `claude` with a
long-running shell so it can exercise tmux behavior without a real
Claude Code binary.

## Per-suite coverage

### `test-init-vault-scaffold.bats`

- Creates `routing-memory.md` with the expected frontmatter and
  "Entry format" section
- Second run does not overwrite an existing routing-memory file
- Fails non-zero when any persona file is missing
- Warns (but exits 0) when `CLAUDE.md` is missing
- Does NOT create `CLAUDE.md` (Andrew owns its content)
- Fails when `VAULT_PATH` does not exist

### `test-start-stop.bats`

- `start-jarvis.sh` creates the tmux session
- Second start is a no-op ("already running")
- `stop-jarvis.sh` removes the session
- Second stop is a no-op ("already stopped")
- `start-jarvis.sh` fails fast when `JARVIS_PROJECT_DIR` is missing
- Uses a `claude` stub binary; no real Claude Code dependency

### `test-health-check.bats`

- Exit 2 (`dead`) when no tmux session exists
- Exit 0 (`ok`) when a session is alive and pane is clean
- Exit 1 (`degraded`) when the pane shows error-looking output

## Sandbox layout

```
tests/.tmp/sandbox.XXXXXX/
├── .env                        # points scripts at the sandbox vault
├── bin/claude                  # stub binary (start-stop suite only)
└── vault/
    ├── 00 Inbox/
    ├── 10 Projects/Jarvis/
    └── 80 Personas/
        ├── Kai - The Kaizen Engineer.md
        ├── Forge - The Platform Engineer.md
        └── Marcus Webb - Platform Product Manager.md
```

The sandbox directory and any test tmux sessions are cleaned up by
`teardown_sandbox_vault` in `tests/helpers.bash`.

## CI (out of scope for v0)

Future-state shape:

```yaml
# .github/workflows/test.yml (sketch — not committed)
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get install -y bats shellcheck tmux
      - run: bash scripts/test.sh
```
