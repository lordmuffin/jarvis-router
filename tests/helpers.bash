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
    mkdir -p "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure"
    mkdir -p "$SANDBOX/vault/80 Personas"
    touch "$SANDBOX/vault/80 Personas/Kai - The Kaizen Engineer.md"
    touch "$SANDBOX/vault/80 Personas/Forge - The Platform Engineer.md"
    touch "$SANDBOX/vault/80 Personas/Marcus Webb - Platform Product Manager.md"
    : > "$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"

    cat > "$SANDBOX/.env" <<EOF
VAULT_PATH="$SANDBOX/vault"
TMUX_SESSION="jarvis-router-test-$$"
JARVIS_PROJECT_DIR="$SANDBOX/vault/10 Projects/Jarvis"
OP_BOT_TOKEN_REF=""
STARTUP_TIMEOUT="5"
FORGE_TMUX_SESSION="forge-test-$$"
FORGE_PROJECT_DIR="$SANDBOX/vault"
FORGE_QUEUE_PATH="$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-queue.md"
FORGE_SYSTEM_PROMPT="$SANDBOX/vault/10 Projects/Jarvis/Infrastructure/forge-system-prompt.md"
FORGE_OP_BOT_TOKEN_REF=""
FORGE_TELEGRAM_CHAT_ID="0"
FORGE_WATCHER_POLL_INTERVAL="1"
FORGE_STARTUP_TIMEOUT="3"
EOF

    export JARVIS_ENV_FILE="$SANDBOX/.env"
    export SANDBOX_SESSION="jarvis-router-test-$$"
    export FORGE_SANDBOX_SESSION="forge-test-$$"
}

teardown_sandbox_vault() {
    if [[ -n "${SANDBOX_SESSION:-}" ]] && tmux has-session -t "$SANDBOX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$SANDBOX_SESSION" 2>/dev/null || true
    fi
    if [[ -n "${FORGE_SANDBOX_SESSION:-}" ]] && tmux has-session -t "$FORGE_SANDBOX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$FORGE_SANDBOX_SESSION" 2>/dev/null || true
    fi
    if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
        rm -rf "$SANDBOX"
    fi
}
