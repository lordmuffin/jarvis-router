#!/usr/bin/env bats

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault

    # The real start-jarvis.sh launches `claude`. For the test we stub
    # it with a long-running shell so tmux behavior is exercised
    # without depending on Claude Code being installed.
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
    teardown_sandbox_vault
}

@test "start-jarvis launches a tmux session" {
    run bash "$REPO_ROOT/scripts/start-jarvis.sh"
    [ "$status" -eq 0 ]
    tmux has-session -t "$SANDBOX_SESSION"
}

@test "start-jarvis is idempotent (second run = no-op)" {
    bash "$REPO_ROOT/scripts/start-jarvis.sh" >/dev/null
    run bash "$REPO_ROOT/scripts/start-jarvis.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already running"* ]]
}

@test "stop-jarvis tears down the session" {
    bash "$REPO_ROOT/scripts/start-jarvis.sh" >/dev/null
    run bash "$REPO_ROOT/scripts/stop-jarvis.sh"
    [ "$status" -eq 0 ]
    run tmux has-session -t "$SANDBOX_SESSION"
    [ "$status" -ne 0 ]
}

@test "stop-jarvis is idempotent (no session = exit 0)" {
    run bash "$REPO_ROOT/scripts/stop-jarvis.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already stopped"* ]]
}

@test "start-jarvis fails fast when JARVIS_PROJECT_DIR is missing" {
    sed -i "s|JARVIS_PROJECT_DIR=.*|JARVIS_PROJECT_DIR=\"$SANDBOX/nope\"|" "$SANDBOX/.env"
    run bash "$REPO_ROOT/scripts/start-jarvis.sh"
    [ "$status" -ne 0 ]
}
