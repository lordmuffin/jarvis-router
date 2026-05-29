# Build and release

There's no compiled artifact. "Build" here means lint + test; "release"
means tagging a known-good revision and following the upgrade dance.

## Lint

```bash
shellcheck scripts/**/*.sh scripts/lib/*.sh
```

Zero warnings is the bar. `scripts/test.sh` runs this for you.

## Test

```bash
bash scripts/test.sh
```

See [testing.md](testing.md) for what's covered.

## Versioning

SemVer in the top-level `VERSION` file. Bump rules:

- **Patch** (`0.1.0 → 0.1.1`) — bug fix, doc edit, internal script change
  with identical CLI/env/file contracts.
- **Minor** (`0.1.0 → 0.2.0`) — new optional script, new env var with a
  safe default, new doc — but no breaking change.
- **Major** (`0.1.0 → 1.0.0`) — breaking change: removed/renamed
  scripts, removed/renamed env vars, changed file contracts (e.g.,
  routing-memory.md format).

## Tag a release

```bash
$EDITOR VERSION         # bump
git commit -am "release vX.Y.Z"
git tag "vX.Y.Z"
git push --tags
```

## Upgrade an installed instance

```bash
cd ~/git/jarvis-router
systemctl --user stop jarvis-router
git fetch --tags
git checkout vX.Y.Z
diff -u .env.example .env || true   # eyeball any new env vars
bash scripts/init-vault-scaffold.sh # re-validates vault state
systemctl --user start jarvis-router
bash scripts/health-check.sh
```

If a major version, read its changelog (if present) or the diff
(`git diff vX-1.Y.Z..vX.Y.Z`) before restarting.

## Reproducible install

Anyone with the vault snapshot can stand up an identical supervisor:

1. Clone the repo at a known tag (`git clone --branch vX.Y.Z`)
2. Follow [setup.md](setup.md)
3. `bash scripts/test.sh` and confirm clean

The repo deliberately holds no state. All state lives in the vault and
in 1Password.
