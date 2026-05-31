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

    cat > "$STUB_BIN/bun" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STUB_BIN/bun"

    export PATH="$STUB_BIN:$PATH"

    # Sandbox the channels state dir so the test never touches the real
    # one at ~/.claude/channels/telegram/.
    export HOME="$SANDBOX/home"
    mkdir -p "$HOME"
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

@test "start-jarvis materializes the op token into the channels .env (0600, single key, no quotes)" {
    # Stub `op` so we don't talk to 1Password — return a fake-but-valid-shaped
    # bot token. `op whoami` must succeed so op_read() doesn't bail early.
    cat > "$STUB_BIN/op" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    whoami) exit 0 ;;
    read)
        # $2 is the op:// ref; we don't care about the value, just emit a token.
        printf '123456789:AAH-fake-stub-token-for-bats-test\n'
        ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$STUB_BIN/op"

    sed -i "s|OP_BOT_TOKEN_REF=.*|OP_BOT_TOKEN_REF=\"op://Stub/bot/token\"|" "$SANDBOX/.env"

    run bash "$REPO_ROOT/scripts/start-jarvis.sh"
    [ "$status" -eq 0 ]

    channels_env="$HOME/.claude/channels/telegram/.env"
    [ -f "$channels_env" ]

    # Exactly one line, exactly the TELEGRAM_BOT_TOKEN= key, no surrounding quotes.
    [ "$(wc -l < "$channels_env")" -eq 1 ]
    grep -q '^TELEGRAM_BOT_TOKEN=123456789:AAH-fake-stub-token-for-bats-test$' "$channels_env"

    # 0600 (-rw-------). %a is the octal mode without the leading 0.
    [ "$(stat -c '%a' "$channels_env")" = "600" ]
}
