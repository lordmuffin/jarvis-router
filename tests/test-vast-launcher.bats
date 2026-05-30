#!/usr/bin/env bats
#
# vast-launcher.sh wraps the Vast.ai REST API. Tests cover env validation
# and the deterministic instance-file path; live API calls are out of scope
# (real launches cost money).

load helpers

setup() {
    mkdir -p "$REPO_ROOT/tests/.tmp"
    setup_sandbox_vault
}

teardown() {
    teardown_sandbox_vault
}

@test "vast-launcher: exits 1 when VAST_API_KEY not set" {
    # Sandbox .env has no VAST_API_KEY by default.
    run bash "$REPO_ROOT/scripts/vast-launcher.sh" create forge
    [ "$status" -eq 1 ]
    [[ "$output" == *"VAST_API_KEY"* ]]
}

@test "vast-launcher: rejects unknown subcommand" {
    sed -i "\$a VAST_API_KEY=\"fake\"" "$SANDBOX/.env"
    run bash "$REPO_ROOT/scripts/vast-launcher.sh" wat forge
    [ "$status" -ne 0 ]
}

@test "vast-launcher: instance_file path is deterministic when sourced" {
    sed -i "\$a VAST_API_KEY=\"fake\"" "$SANDBOX/.env"
    run bash -c "source '$REPO_ROOT/scripts/vast-launcher.sh' >/dev/null 2>&1; instance_file forge"
    [ "$status" -eq 0 ]
    [[ "$output" == "/tmp/vast-forge.instance" ]]
}
