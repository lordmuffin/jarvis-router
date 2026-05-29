#!/usr/bin/env bats

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
}

teardown() {
    teardown_sandbox_vault
}

@test "exits 2 (dead) when tmux session does not exist" {
    run bash "$REPO_ROOT/scripts/health-check.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"dead"* ]]
}

@test "exits 0 (ok) when a session exists" {
    tmux new-session -d -s "$SANDBOX_SESSION" "sleep 60"
    run bash "$REPO_ROOT/scripts/health-check.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "exits 1 (degraded) when pane shows error-looking output" {
    tmux new-session -d -s "$SANDBOX_SESSION" "bash -c 'echo ERROR: something broke; sleep 60'"
    # Give tmux a moment to render the line into the pane.
    sleep 1
    run bash "$REPO_ROOT/scripts/health-check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"degraded"* ]]
}
