#!/usr/bin/env bash
# Seed the vault files Jarvis expects at runtime. Idempotent.
#
# Creates `routing-memory.md` if missing. Verifies presence of the four
# routing-target files (CLAUDE.md routing identity + three persona files
# + the operator notion which is implicit). Reports a summary.
#
# Exits non-zero if any required file is missing AND was not created.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

JARVIS_DIR="$JARVIS_PROJECT_DIR"
PERSONAS_DIR="$VAULT_PATH/80 Personas"
INBOX_DIR="$VAULT_PATH/00 Inbox"
ROUTING_MEMORY="$JARVIS_DIR/routing-memory.md"
ROUTING_IDENTITY="$JARVIS_DIR/CLAUDE.md"

created=()
present=()
missing=()

note_present() { present+=("$1"); }
note_missing() { missing+=("$1"); }
note_created() { created+=("$1"); }

check_file() {
    local path="$1"
    if [[ -f "$path" ]]; then
        note_present "$path"
        return 0
    else
        note_missing "$path"
        return 1
    fi
}

check_dir() {
    local path="$1"
    if [[ -d "$path" ]]; then
        note_present "$path/"
        return 0
    else
        note_missing "$path/"
        return 1
    fi
}

# Required directories
check_dir "$VAULT_PATH"      || die "VAULT_PATH does not exist: $VAULT_PATH"
check_dir "$JARVIS_DIR"      || die "Jarvis project dir missing: $JARVIS_DIR"
check_dir "$PERSONAS_DIR"    || die "Personas dir missing: $PERSONAS_DIR"
check_dir "$INBOX_DIR"       || die "Inbox dir missing: $INBOX_DIR"

# Routing identity (CLAUDE.md). We do NOT create it — Andrew owns its
# content. We only report whether it's present.
check_file "$ROUTING_IDENTITY" || \
    warn "Routing identity missing: $ROUTING_IDENTITY (create by hand — Jarvis will run without an identity until you do)"

# Persona files (glob to tolerate small filename variations).
shopt -s nullglob
kai_files=("$PERSONAS_DIR"/Kai*.md)
forge_files=("$PERSONAS_DIR"/Forge*.md)
marcus_files=("$PERSONAS_DIR"/Marcus*Webb*.md)
shopt -u nullglob

if [[ ${#kai_files[@]} -gt 0 ]]; then
    note_present "${kai_files[0]}"
else
    note_missing "$PERSONAS_DIR/Kai*.md"
fi

if [[ ${#forge_files[@]} -gt 0 ]]; then
    note_present "${forge_files[0]}"
else
    note_missing "$PERSONAS_DIR/Forge*.md"
fi

if [[ ${#marcus_files[@]} -gt 0 ]]; then
    note_present "${marcus_files[0]}"
else
    note_missing "$PERSONAS_DIR/Marcus*Webb*.md"
fi

# Routing memory: create if missing, with a usable header.
if [[ ! -f "$ROUTING_MEMORY" ]]; then
    today="$(date +%Y-%m-%d)"
    cat > "$ROUTING_MEMORY" <<EOF
---
created: $today
type: routing-memory
tags: [jarvis, routing, memory]
---

# Jarvis Routing Memory

Append-only pattern log. Jarvis reads this before every routing decision
to apply learned patterns about Andrew's vocabulary and habits.

## Entry format

Each entry is one line:

\`\`\`
[YYYY-MM-DD] pattern: "<phrase or vocabulary>" -> persona: <Kai|Forge|Marcus|operator> (confidence: low|med|high) -- note: <why>
\`\`\`

Higher-confidence entries beat lower-confidence ones for the same pattern.
Manual overrides (slash commands) never write entries; only auto-routes
that Andrew did or did not correct become memory.

## Entries

<!-- Example (commented out — uncomment or delete):
[$today] pattern: "the box" -> persona: Forge (confidence: high) -- note: shorthand for homelab server
-->

EOF
    note_created "$ROUTING_MEMORY"
else
    note_present "$ROUTING_MEMORY"
fi

# Summary
echo
echo "=== Vault scaffold summary ==="
echo
if [[ ${#present[@]} -gt 0 ]]; then
    echo "Present (${#present[@]}):"
    printf '  ok   %s\n' "${present[@]}"
fi
if [[ ${#created[@]} -gt 0 ]]; then
    echo "Created (${#created[@]}):"
    printf '  new  %s\n' "${created[@]}"
fi
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing (${#missing[@]}):"
    printf '  MISS %s\n' "${missing[@]}"
fi
echo

# Personas missing is fatal. Routing identity missing is a warning (above).
required_personas_ok=1
[[ ${#kai_files[@]}    -eq 0 ]] && required_personas_ok=0
[[ ${#forge_files[@]}  -eq 0 ]] && required_personas_ok=0
[[ ${#marcus_files[@]} -eq 0 ]] && required_personas_ok=0

if [[ $required_personas_ok -eq 0 ]]; then
    die "One or more required persona files are missing. Jarvis cannot route without them."
fi

log "Scaffold OK."
