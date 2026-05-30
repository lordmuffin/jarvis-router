#!/usr/bin/env bats
#
# gaming-pc-launcher.sh controls Ollama on the gaming PC over SSH. Tests
# cover the fail-fast paths (config missing, host unreachable) — we don't
# exercise the real SSH or Ollama HTTP calls.

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
}

teardown() {
    teardown_sandbox_vault
}

@test "gaming-pc-launcher: exits 1 when GAMING_PC_HOST is empty" {
    # Sandbox .env has no GAMING_PC_HOST — script must fail fast.
    run bash "$REPO_ROOT/scripts/gaming-pc-launcher.sh" status
    [ "$status" -eq 1 ]
    [[ "$output" == *"GAMING_PC_HOST"* ]]
}

@test "gaming-pc-launcher: 'available' returns 1 when host unreachable" {
    # 192.0.2.1 is in TEST-NET-1 (RFC 5737) — guaranteed unreachable.
    sed -i "\$a GAMING_PC_HOST=\"192.0.2.1\"" "$SANDBOX/.env"
    run bash "$REPO_ROOT/scripts/gaming-pc-launcher.sh" available
    [ "$status" -eq 1 ]
}

@test "gaming-pc-launcher: rejects unknown subcommand" {
    sed -i "\$a GAMING_PC_HOST=\"localhost\"" "$SANDBOX/.env"
    run bash "$REPO_ROOT/scripts/gaming-pc-launcher.sh" frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage"* || "$output" == *"unknown"* ]]
}
