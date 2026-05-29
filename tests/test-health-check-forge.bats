#!/usr/bin/env bats

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
    # Make sure no Forge sandbox session exists from a prior run.
    tmux kill-session -t "$FORGE_SANDBOX_SESSION" 2>/dev/null || true
    # The Forge status section reads /tmp/forge-watcher.log if present.
    # Start from a known state.
    rm -f /tmp/forge-watcher.log
}

teardown() {
    teardown_sandbox_vault
    rm -f /tmp/forge-watcher.log
}

@test "health_check: output contains forge status line" {
    # A live Kai session is required for the existing health-check to
    # exit cleanly enough to print the Forge line — start a sleeper.
    tmux new-session -d -s "$SANDBOX_SESSION" "sleep 60"
    run bash "$REPO_ROOT/scripts/health-check.sh"
    [[ "$output" == *"forge:"* ]]
}

@test "health_check: shows forge idle when no Forge tmux session" {
    tmux new-session -d -s "$SANDBOX_SESSION" "sleep 60"
    run bash "$REPO_ROOT/scripts/health-check.sh"
    [[ "$output" == *"forge: idle"* ]]
}

@test "health_check: shows last 3 lines of /tmp/forge-watcher.log if present" {
    tmux new-session -d -s "$SANDBOX_SESSION" "sleep 60"
    printf 'line1\nline2\nline3\nline4\n' > /tmp/forge-watcher.log
    run bash "$REPO_ROOT/scripts/health-check.sh"
    [[ "$output" == *"line2"* ]] || [[ "$output" == *"line3"* ]] || [[ "$output" == *"line4"* ]]
}
