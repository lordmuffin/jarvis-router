#!/usr/bin/env bats

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
}

teardown() {
    teardown_sandbox_vault
}

@test "creates routing-memory.md when missing" {
    run bash "$REPO_ROOT/scripts/init-vault-scaffold.sh"
    [ "$status" -eq 0 ]
    [ -f "$SANDBOX/vault/10 Projects/Jarvis/routing-memory.md" ]
    grep -q "type: routing-memory" "$SANDBOX/vault/10 Projects/Jarvis/routing-memory.md"
    grep -q "Entry format" "$SANDBOX/vault/10 Projects/Jarvis/routing-memory.md"
}

@test "is idempotent — second run does not overwrite existing routing-memory" {
    run bash "$REPO_ROOT/scripts/init-vault-scaffold.sh"
    [ "$status" -eq 0 ]
    echo "manual edit" >> "$SANDBOX/vault/10 Projects/Jarvis/routing-memory.md"

    run bash "$REPO_ROOT/scripts/init-vault-scaffold.sh"
    [ "$status" -eq 0 ]
    grep -q "manual edit" "$SANDBOX/vault/10 Projects/Jarvis/routing-memory.md"
}

@test "fails when a persona file is missing" {
    rm "$SANDBOX/vault/80 Personas/Kai - The Kaizen Engineer.md"
    run bash "$REPO_ROOT/scripts/init-vault-scaffold.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"persona"* ]] || [[ "$output" == *"Kai"* ]]
}

@test "warns when routing identity (CLAUDE.md) is missing but still exits 0" {
    run bash "$REPO_ROOT/scripts/init-vault-scaffold.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Routing identity missing"* ]] || [[ "$output" == *"CLAUDE.md"* ]]
}

@test "does not create CLAUDE.md (Andrew owns its content)" {
    bash "$REPO_ROOT/scripts/init-vault-scaffold.sh" >/dev/null 2>&1 || true
    [ ! -f "$SANDBOX/vault/10 Projects/Jarvis/CLAUDE.md" ]
}

@test "fails when VAULT_PATH does not exist" {
    sed -i "s|VAULT_PATH=.*|VAULT_PATH=\"/nonexistent/path/$$\"|" "$SANDBOX/.env"
    run bash "$REPO_ROOT/scripts/init-vault-scaffold.sh"
    [ "$status" -ne 0 ]
}
