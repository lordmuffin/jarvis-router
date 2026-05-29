#!/usr/bin/env bats

load helpers

# These tests exercise start-forge.sh end-to-end by stubbing tmux,
# claude, op, and curl in a sandboxed bin dir prepended to PATH. The
# tmux stub keeps a counter on disk (TMUX_STUB_ALIVE_FOR has-session
# calls until "session" dies) so we can simulate clean exit vs. crash
# deterministically without ever launching a real tmux process.

stub_bins() {
    STUB_BIN="$SANDBOX/bin"
    mkdir -p "$STUB_BIN"

    cat > "$STUB_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
sub="$1"; shift
case "$sub" in
    new-session)
        echo "${TMUX_STUB_ALIVE_FOR:-2}" > "${SANDBOX}/tmux_alive_count"
        exit 0
        ;;
    has-session)
        counter="${SANDBOX}/tmux_alive_count"
        n=$(cat "$counter" 2>/dev/null || echo 0)
        if [[ "$n" -gt 0 ]]; then
            echo $((n - 1)) > "$counter"
            exit 0
        fi
        exit 1
        ;;
    kill-session)
        rm -f "${SANDBOX}/tmux_alive_count"
        exit 0
        ;;
    capture-pane) echo "stub pane output"; exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/tmux"

    cat > "$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
sleep 60
EOF
    chmod +x "$STUB_BIN/claude"

    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "${SANDBOX}/curl_calls.log"
exit 0
EOF
    chmod +x "$STUB_BIN/curl"

    cat > "$STUB_BIN/op" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    whoami) exit 0 ;;
    read)   echo "FAKE_FORGE_TOKEN"; exit 0 ;;
    *)      exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/op"

    export PATH="$STUB_BIN:$PATH"
}

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
    stub_bins
    rm -f /tmp/forge-start.log
    # Configure a real-looking 1Password ref so notify_telegram fires.
    sed -i.bak 's|^FORGE_OP_BOT_TOKEN_REF=.*|FORGE_OP_BOT_TOKEN_REF="op://fake/forgebot/token"|' \
        "$SANDBOX/.env"
}

teardown() {
    teardown_sandbox_vault
}

# --- env validation -------------------------------------------------------

@test "start_forge: exits non-zero if VAULT_PATH not set in environment" {
    # Point JARVIS_ENV_FILE at a non-existent file and clear env, so
    # load_env has no .env to source and no VAULT_PATH to fall back on.
    run env -i HOME="$HOME" PATH="$PATH" \
        JARVIS_ENV_FILE="$SANDBOX/nonexistent.env" \
        bash "$REPO_ROOT/scripts/start-forge.sh"
    [ "$status" -ne 0 ]
}

# --- log writing ----------------------------------------------------------

@test "start_forge: writes a line to /tmp/forge-start.log" {
    TMUX_STUB_ALIVE_FOR=2 run bash "$REPO_ROOT/scripts/start-forge.sh"
    [ -f /tmp/forge-start.log ]
}

@test "start_forge: log contains a success or failure verdict line" {
    TMUX_STUB_ALIVE_FOR=2 bash "$REPO_ROOT/scripts/start-forge.sh" || true
    run grep -E "success|fail|RUNNING|not found" /tmp/forge-start.log
    [ "$status" -eq 0 ]
}

# --- crash handling -------------------------------------------------------

@test "start_forge: appends ## Paused when session dies with unchecked Active items" {
    printf '## Active\n- [ ] half-done task\n## Done\n' \
        > "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    TMUX_STUB_ALIVE_FOR=2 run bash "$REPO_ROOT/scripts/start-forge.sh"
    [ "$status" -ne 0 ]
    grep -q '^## Paused' "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    grep -q 'half-done task' "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
}

@test "start_forge: invokes Telegram API on crash" {
    printf '## Active\n- [ ] half-done task\n## Done\n' \
        > "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    TMUX_STUB_ALIVE_FOR=2 bash "$REPO_ROOT/scripts/start-forge.sh" || true
    [ -f "$SANDBOX/curl_calls.log" ]
    grep -q 'api.telegram.org' "$SANDBOX/curl_calls.log"
}

@test "start_forge: exits 0 and writes no ## Paused when Active section is clear" {
    printf '## Active\n- [x] already done\n## Done\n' \
        > "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    TMUX_STUB_ALIVE_FOR=2 run bash "$REPO_ROOT/scripts/start-forge.sh"
    [ "$status" -eq 0 ]
    run grep '^## Paused' "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    [ "$status" -ne 0 ]
}

@test "start_forge: does NOT call Telegram API on clean exit" {
    printf '## Active\n- [x] already done\n## Done\n' \
        > "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    TMUX_STUB_ALIVE_FOR=2 bash "$REPO_ROOT/scripts/start-forge.sh" || true
    [ ! -f "$SANDBOX/curl_calls.log" ] || \
        ! grep -q 'api.telegram.org' "$SANDBOX/curl_calls.log"
}

@test "start_forge: ## Paused append is idempotent (no duplicate header)" {
    cat > "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md" <<EOF
## Active
- [ ] half-done task

## Paused
- [ ] earlier paused task

## Done
EOF
    TMUX_STUB_ALIVE_FOR=2 bash "$REPO_ROOT/scripts/start-forge.sh" || true
    # Exactly one "## Paused" header.
    run grep -c '^## Paused' "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    # New task is in the file under Paused.
    grep -q 'half-done task' "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
}
