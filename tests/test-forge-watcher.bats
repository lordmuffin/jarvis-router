#!/usr/bin/env bats

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
    # Source the library so we can call active_queue_has_unchecked
    # directly. VAULT_PATH+TMUX_SESSION are required by load_env even
    # though we don't call load_env here; the helpers themselves only
    # need access to the awk and curl logic.
    # shellcheck disable=SC1091
    . "$REPO_ROOT/scripts/lib/common.sh"
}

teardown() {
    teardown_sandbox_vault
}

# --- active_queue_has_unchecked -------------------------------------------
#
# NOTE on awk: the build prompt's literal one-liner used
#   `... /^- \[ \]/{exit 0} END{exit 1}`
# but `END` runs after any `exit`, and a second `exit` in `END`
# overrides the earlier status, so that pattern returns 1 even on a
# valid Active item. The helper (and these tests) use the corrected
# `hit=1; exit` + `END{exit !hit}` form.

@test "active_queue_has_unchecked: succeeds when Active section has unchecked item" {
    local f="$SANDBOX/q1.md"
    printf '## Active\n- [ ] do something\n## Done\n' > "$f"
    run active_queue_has_unchecked "$f"
    [ "$status" -eq 0 ]
}

@test "active_queue_has_unchecked: fails when Active section is empty" {
    local f="$SANDBOX/q2.md"
    printf '## Active\n\n## Done\n' > "$f"
    run active_queue_has_unchecked "$f"
    [ "$status" -ne 0 ]
}

@test "active_queue_has_unchecked: fails when Active section only has checked items" {
    local f="$SANDBOX/q3.md"
    printf '## Active\n- [x] already done\n## Done\n' > "$f"
    run active_queue_has_unchecked "$f"
    [ "$status" -ne 0 ]
}

@test "active_queue_has_unchecked: fails when no Active section present" {
    local f="$SANDBOX/q4.md"
    printf '## Backlog\n- [ ] staged task\n' > "$f"
    run active_queue_has_unchecked "$f"
    [ "$status" -ne 0 ]
}

@test "active_queue_has_unchecked: fails when file does not exist" {
    run active_queue_has_unchecked "$SANDBOX/does-not-exist.md"
    [ "$status" -ne 0 ]
}

# --- forge-watcher.sh guards ---------------------------------------------

@test "forge_watcher: exits 1 if inotifywait missing and queue file absent" {
    # Hide inotifywait by prepending a sandbox bin containing only
    # well-known system binaries (no inotifywait). Point queue at a
    # missing path. Keep /bin and /usr/bin on PATH so bash itself works.
    rm -f "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    sed -i.bak "s|^FORGE_QUEUE_PATH=.*|FORGE_QUEUE_PATH=\"$SANDBOX/missing-queue.md\"|" \
        "$SANDBOX/.env"
    local stubdir="$SANDBOX/stubbin"
    mkdir -p "$stubdir"
    # Restrict PATH to system dirs only — inotifywait is brew-installed
    # on this host (if at all), so this is enough to hide it.
    run env -i HOME="$HOME" PATH="$stubdir:/usr/bin:/bin" \
        JARVIS_ENV_FILE="$SANDBOX/.env" \
        bash "$REPO_ROOT/scripts/forge-watcher.sh"
    [ "$status" -eq 1 ]
}
