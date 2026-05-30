#!/usr/bin/env bats
#
# Rule-based pre-classifier. Conservative by design — only matches
# unambiguous patterns. Anything that requires reasoning falls through
# to Kai (exit 1).

load helpers

@test "classifier: routes 'forge build this' to forge" {
    run bash "$REPO_ROOT/scripts/classifier.sh" "forge build this thing"
    [ "$status" -eq 0 ]
    [ "$output" = "forge" ]
}

@test "classifier: routes 'deploy this' to forge" {
    run bash "$REPO_ROOT/scripts/classifier.sh" "deploy this container"
    [ "$status" -eq 0 ]
    [ "$output" = "forge" ]
}

@test "classifier: routes 'transcribe audio file' to transcription" {
    run bash "$REPO_ROOT/scripts/classifier.sh" "transcribe this audio file please"
    [ "$status" -eq 0 ]
    [ "$output" = "transcription" ]
}

@test "classifier: routes 'start voice' to voice" {
    run bash "$REPO_ROOT/scripts/classifier.sh" "start voice mode"
    [ "$status" -eq 0 ]
    [ "$output" = "voice" ]
}

@test "classifier: passes ambiguous message to kai" {
    run bash "$REPO_ROOT/scripts/classifier.sh" "what should I focus on today?"
    [ "$status" -eq 1 ]
    [ "$output" = "kai" ]
}

@test "classifier: errors when called with no argument" {
    run bash "$REPO_ROOT/scripts/classifier.sh"
    [ "$status" -ne 0 ]
}

@test "classifier: is case-insensitive" {
    run bash "$REPO_ROOT/scripts/classifier.sh" "FORGE BUILD THIS"
    [ "$status" -eq 0 ]
    [ "$output" = "forge" ]
}
