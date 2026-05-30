#!/usr/bin/env bash
# Bring up the transcription tmux session — a oneshot worker that drains
# `${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/transcription-queue.md`
# using faster-whisper or whisper.cpp and notifies Telegram on completion.
#
# Idempotent. Returns 0 if the session is already running.

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

load_env

: "${TRANSCRIPTION_TMUX_SESSION:=transcription}"
: "${TRANSCRIPTION_TOOL:=whisper-cli}"   # whisper-cli (whisper.cpp) or faster-whisper
: "${TELEGRAM_CHAT_ID:=}"

QUEUE="${VAULT_PATH}/10 Projects/Jarvis/Infrastructure/transcription-queue.md"

if tmux_session_alive "$TRANSCRIPTION_TMUX_SESSION"; then
    log "Transcription session already running. Nothing to do."
    exit 0
fi

command -v tmux >/dev/null 2>&1 || die "tmux not found on PATH"
if [[ ! -f "$QUEUE" ]]; then
    die "Transcription queue not found: $QUEUE. Run init-vault-scaffold.sh or create it manually."
fi

# The worker is a small shell loop that picks each Active path, runs the
# transcription tool, and moves the entry to Done. We launch it inside the
# tmux session so Andrew can attach mid-run if needed.
worker_script="$(cat <<'WORKER'
set -uo pipefail
QUEUE_PATH="$1"
TOOL="$2"
START_TS="$(date -Iseconds)"
COUNT=0

while :; do
  path="$(awk '/^## Active/{f=1; next} f && /^## /{f=0} f && /^- \[ \] /{ sub(/^- \[ \] /,""); print; exit}' "$QUEUE_PATH")"
  [[ -z "$path" ]] && break

  echo "[$(date '+%H:%M:%S')] transcribing: $path"
  if [[ ! -f "$path" ]]; then
    echo "  skip: file not found"
  elif command -v "$TOOL" >/dev/null 2>&1; then
    out="${path%.*}.txt"
    "$TOOL" -f "$path" -of "${path%.*}" 2>&1 || echo "  failed: $TOOL exit $?"
    [[ -f "$out" ]] && echo "  -> $out"
  else
    echo "  skip: $TOOL not on PATH"
  fi

  # Move from Active -> Done. Awk-based rewrite to avoid sed pitfalls with paths.
  tmp="$(mktemp)"
  awk -v target="- [ ] $path" '
    BEGIN{moved=0}
    {
      if ($0 == target && moved == 0) { moved=1; next }
      print
    }
    END{
      # Append checkbox to ## Done by re-emitting (handled by post-pass).
    }
  ' "$QUEUE_PATH" > "$tmp"
  # Append "- [x] <path>" under ## Done (create section if missing).
  if ! grep -q '^## Done' "$tmp"; then
    printf '\n## Done\n' >> "$tmp"
  fi
  awk -v line="- [x] $path" '
    {print}
    /^## Done/ && !done {print line; done=1}
  ' "$tmp" > "$QUEUE_PATH"
  rm -f "$tmp"

  COUNT=$((COUNT + 1))
done

echo "[$(date '+%H:%M:%S')] queue drained. transcribed: $COUNT  started: $START_TS"
WORKER
)"

log "Starting transcription session '$TRANSCRIPTION_TMUX_SESSION' ..."
tmux new-session -d -s "$TRANSCRIPTION_TMUX_SESSION" -c "$VAULT_PATH" \
    "bash -c '$worker_script' worker '$QUEUE' '$TRANSCRIPTION_TOOL'; echo done; sleep 5"

# Best-effort completion notification: fork a watcher that fires when the
# session ends.
(
    while tmux has-session -t "$TRANSCRIPTION_TMUX_SESSION" 2>/dev/null; do
        sleep 5
    done
    telegram_notify "📝 Transcription queue drained" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
) >/dev/null 2>&1 &

log "Transcription session up. Attach: tmux attach -t $TRANSCRIPTION_TMUX_SESSION"
exit 0
