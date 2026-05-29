# tests/

Bash script tests using [bats-core](https://bats-core.readthedocs.io/).

## Run

```bash
bats tests/                    # all suites
bats tests/test-health-check.bats   # one suite
bash scripts/test.sh           # shellcheck + bats
```

## How isolation works

Each test calls `setup_sandbox_vault` (in `helpers.bash`) which creates:

- `tests/.tmp/sandbox.XXXXXX/` — a fresh sandbox per test
- `<sandbox>/vault/` — minimal vault tree (`00 Inbox/`, `10 Projects/Jarvis/`,
  `80 Personas/` with three empty persona files)
- `<sandbox>/.env` — points scripts at the sandbox
- `tmux` session names prefixed `jarvis-router-test-<pid>` to avoid
  collision with the user's real session

`teardown_sandbox_vault` kills the test session and removes the sandbox
dir.

Scripts pick up the sandbox `.env` via the `JARVIS_ENV_FILE` env var
(`scripts/lib/common.sh` honors it).

## Per-suite coverage

| File                              | Covers                                                      |
|-----------------------------------|-------------------------------------------------------------|
| `test-init-vault-scaffold.bats`   | scaffold creation, idempotency, missing-persona failure, CLAUDE.md is NOT created |
| `test-start-stop.bats`            | tmux lifecycle, idempotent start, idempotent stop (uses a `claude` stub) |
| `test-health-check.bats`          | exit codes: 0 ok, 1 degraded, 2 dead                        |

We do NOT test Jarvis's routing decisions here — those are LLM
behaviors validated by the manual smoke tests in the main README.
