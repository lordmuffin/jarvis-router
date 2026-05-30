#!/usr/bin/env bats
#
# Active-item detection is the single most important piece of routing logic
# in the watcher: a false negative means Forge never starts; a false positive
# means runaway sessions. Cover the awk one-liner with the four canonical
# queue shapes, then sanity-check the watcher's prereq failure path.

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
}

@test "active_item_detection: succeeds when Active section has unchecked item" {
    local f; f=$(mktemp)
    printf '## Active\n- [ ] do something\n## Done\n' > "$f"
    run awk '
        /^## Active/ { f=1; next }
        f && /^## / { f=0 }
        f && /^- \[ \]/ { m=1; exit }
        END { exit !m }
    ' "$f"
    [ "$status" -eq 0 ]
    rm "$f"
}

@test "active_item_detection: fails when Active section is empty" {
    local f; f=$(mktemp)
    printf '## Active\n\n## Done\n' > "$f"
    run awk '
        /^## Active/ { f=1; next }
        f && /^## / { f=0 }
        f && /^- \[ \]/ { m=1; exit }
        END { exit !m }
    ' "$f"
    [ "$status" -eq 1 ]
    rm "$f"
}

@test "active_item_detection: fails when Active section only has checked items" {
    local f; f=$(mktemp)
    printf '## Active\n- [x] already done\n## Done\n' > "$f"
    run awk '
        /^## Active/ { f=1; next }
        f && /^## / { f=0 }
        f && /^- \[ \]/ { m=1; exit }
        END { exit !m }
    ' "$f"
    [ "$status" -eq 1 ]
    rm "$f"
}

@test "active_item_detection: fails when no Active section present" {
    local f; f=$(mktemp)
    printf '## Backlog\n- [ ] staged task\n' > "$f"
    run awk '
        /^## Active/ { f=1; next }
        f && /^## / { f=0 }
        f && /^- \[ \]/ { m=1; exit }
        END { exit !m }
    ' "$f"
    [ "$status" -eq 1 ]
    rm "$f"
}

@test "forge-watcher: exits 1 when inotifywait missing AND queue file absent" {
    # Empty PATH ensures inotifywait is unreachable; the sandbox has no
    # queue file. Invoke bash by absolute path so PATH=empty doesn't break
    # the launcher itself.
    setup_sandbox_vault
    local empty; empty=$(mktemp -d)
    local bash_bin; bash_bin="$(command -v bash)"
    PATH="$empty" JARVIS_ENV_FILE="$SANDBOX/.env" \
        run "$bash_bin" "$REPO_ROOT/scripts/forge-watcher.sh"
    [ "$status" -eq 1 ]
    rm -rf "$empty"
    teardown_sandbox_vault
}
