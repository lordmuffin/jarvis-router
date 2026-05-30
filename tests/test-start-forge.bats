#!/usr/bin/env bats
#
# start-forge.sh wraps Claude Code in a tmux session named `forge`, writes a
# verdict to /tmp/forge-start.log, and notifies Telegram on failures. We stub
# `claude` so we don't depend on Claude Code being installed.

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault

    # Forge session name is hardcoded by spec; isolate per-PID to avoid
    # colliding with a real forge session on the host.
    export FORGE_TMUX_SESSION="forge-test-$$"
    sed -i "\$a FORGE_TMUX_SESSION=\"$FORGE_TMUX_SESSION\"" "$SANDBOX/.env"

    STUB_BIN="$SANDBOX/bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "stub claude alive"
sleep 60
EOF
    chmod +x "$STUB_BIN/claude"
    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    if tmux has-session -t "$FORGE_TMUX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$FORGE_TMUX_SESSION" 2>/dev/null || true
    fi
    teardown_sandbox_vault
}

@test "start-forge: exits non-zero when VAULT_PATH not set" {
    run env -i HOME="$HOME" PATH="$PATH" bash "$REPO_ROOT/scripts/start-forge.sh"
    [ "$status" -ne 0 ]
}

@test "start-forge: writes a verdict line to /tmp/forge-start.log" {
    rm -f /tmp/forge-start.log
    run bash "$REPO_ROOT/scripts/start-forge.sh"
    [ -f /tmp/forge-start.log ]
    run grep -E "started|failed|already running" /tmp/forge-start.log
    [ "$status" -eq 0 ]
}

@test "start-forge: launches tmux session and is idempotent" {
    bash "$REPO_ROOT/scripts/start-forge.sh" >/dev/null
    tmux has-session -t "$FORGE_TMUX_SESSION"
    run bash "$REPO_ROOT/scripts/start-forge.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already running"* ]]
}
