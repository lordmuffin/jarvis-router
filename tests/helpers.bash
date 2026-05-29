#!/usr/bin/env bash
# Common test setup. Each test gets its own sandbox vault under
# tests/.tmp/<random>/ so suites are isolated from the real vault.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

setup_sandbox_vault() {
    SANDBOX="$(mktemp -d "${REPO_ROOT}/tests/.tmp/sandbox.XXXXXX")"
    export SANDBOX

    mkdir -p "$SANDBOX/vault/00 Inbox"
    mkdir -p "$SANDBOX/vault/10 Projects/Jarvis"
    mkdir -p "$SANDBOX/vault/80 Personas"
    touch "$SANDBOX/vault/80 Personas/Kai - The Kaizen Engineer.md"
    touch "$SANDBOX/vault/80 Personas/Forge - The Platform Engineer.md"
    touch "$SANDBOX/vault/80 Personas/Marcus Webb - Platform Product Manager.md"

    cat > "$SANDBOX/.env" <<EOF
VAULT_PATH="$SANDBOX/vault"
TMUX_SESSION="jarvis-router-test-$$"
JARVIS_PROJECT_DIR="$SANDBOX/vault/10 Projects/Jarvis"
OP_BOT_TOKEN_REF=""
STARTUP_TIMEOUT="5"
EOF

    export JARVIS_ENV_FILE="$SANDBOX/.env"
    export SANDBOX_SESSION="jarvis-router-test-$$"
}

teardown_sandbox_vault() {
    if [[ -n "${SANDBOX_SESSION:-}" ]] && tmux has-session -t "$SANDBOX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$SANDBOX_SESSION" 2>/dev/null || true
    fi
    if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
        rm -rf "$SANDBOX"
    fi
}
