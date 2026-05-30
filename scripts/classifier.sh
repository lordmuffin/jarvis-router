#!/usr/bin/env bash
# Rule-based intent pre-classifier. Runs on CPU before any LLM call.
#
# Usage: classifier.sh "<message-text>"
#
# Stdout:
#   forge | transcription | voice | kai
#
# Exit:
#   0  → classified (caller should dispatch to the named workload)
#   1  → ambiguous, output is "kai" (caller should hand off to LLM routing)
#   2  → usage error
#
# Conservative by design. False negatives (missing a forge intent) are
# better than false positives (routing a real question to a batch handler).
# Anything not matching an unambiguous regex falls through to kai.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    printf 'usage: classifier.sh "<message>"\n' >&2
    exit 2
fi

msg_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

# Forge triggers — explicit build/deploy/infra verbs.
if printf '%s' "$msg_lc" | grep -qE '(^|[[:space:]])(forge|build this|deploy|debug infra|lxc|container|k8s|kubectl)([[:space:]]|$)'; then
    printf 'forge\n'
    exit 0
fi

# Transcription triggers — audio file references and explicit verbs.
if printf '%s' "$msg_lc" | grep -qE '(transcri(be|ption)|whisper|audio file|\.mp3|\.m4a|\.wav)'; then
    printf 'transcription\n'
    exit 0
fi

# Voice stack triggers — TTS / wake words.
if printf '%s' "$msg_lc" | grep -qE '(start (voice|kai voice|tts)|wake (up )?kai|voice mode)'; then
    printf 'voice\n'
    exit 0
fi

printf 'kai\n'
exit 1
