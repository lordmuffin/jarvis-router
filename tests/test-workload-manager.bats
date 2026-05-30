#!/usr/bin/env bats
#
# workload-start/stop are the unified front door for forge/transcription/voice.
# Idempotency is the load-bearing invariant: calling start twice for the same
# workload must be a no-op, never a second session.

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
}

teardown() {
    teardown_sandbox_vault
}

@test "workload-start: rejects unknown workload type" {
    run bash "$REPO_ROOT/scripts/workload-start.sh" frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown workload"* ]]
}

@test "workload-start: is idempotent when target session already running" {
    # Stub tmux to claim the session exists for any has-session query.
    local stubdir; stubdir=$(mktemp -d)
    cat > "$stubdir/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$stubdir/tmux"
    PATH="$stubdir:$PATH" run bash "$REPO_ROOT/scripts/workload-start.sh" forge
    [ "$status" -eq 0 ]
    [[ "$output" == *"already running"* ]]
    rm -rf "$stubdir"
}

@test "workload-stop: exits cleanly when nothing is running" {
    # Stub tmux to claim no session exists and accept kill-session as no-op.
    local stubdir; stubdir=$(mktemp -d)
    cat > "$stubdir/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  kill-session) exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$stubdir/tmux"
    PATH="$stubdir:$PATH" run bash "$REPO_ROOT/scripts/workload-stop.sh" forge
    [ "$status" -eq 0 ]
    [[ "$output" == *"already stopped"* || "$output" == *"nothing to stop"* ]]
    rm -rf "$stubdir"
}

@test "is_gpu_busy: true when sourced and any workload session is alive" {
    local stubdir; stubdir=$(mktemp -d)
    cat > "$stubdir/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$stubdir/tmux"
    run bash -c "PATH='$stubdir:\$PATH'; source '$REPO_ROOT/scripts/workload-start.sh' >/dev/null 2>&1; is_gpu_busy && echo busy"
    [[ "$output" == *"busy"* ]]
    rm -rf "$stubdir"
}
