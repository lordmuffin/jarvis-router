#!/usr/bin/env bash
# Vast.ai REST API wrapper for on-demand cloud GPU launches.
#
# Subcommands:
#   create  <workload-type>   provision instance, write ID to /tmp/vast-<type>.instance
#   status  <workload-type>   GET current state from Vast.ai
#   destroy <workload-type>   terminate instance and clear the ID file
#
# Env:
#   VAST_API_KEY              required for all subcommands
#
# Errors (rate limits, no instances, insufficient funds) are logged and
# best-effort notified via Telegram.

# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

VAST_API_BASE="https://console.vast.ai/api/v0"

# Workload spec: A100 80GB, prefer spot pricing, Ubuntu 22.04 w/ CUDA.
#   gpu_name=A100 minimum, RAM 60GB, disk 100GB, spot prefer.
# Conservative search query; tighten/widen via env if needed.
VAST_SEARCH_QUERY_DEFAULT='{"gpu_name":{"eq":"A100"},"verified":{"eq":true},"rentable":{"eq":true},"reliability2":{"gte":0.95},"order":[["dph_total","asc"]]}'

instance_file() {
    printf '/tmp/vast-%s.instance\n' "$1"
}

load_env_if_present() {
    local env_file="${JARVIS_ENV_FILE:-${REPO_ROOT}/.env}"
    if [[ -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
    fi
}

require_api_key() {
    if [[ -z "${VAST_API_KEY:-}" ]]; then
        err "VAST_API_KEY not set in .env. Add it: VAST_API_KEY=<your-key>"
        exit 1
    fi
    command -v curl >/dev/null 2>&1 || die "curl not on PATH"
    command -v jq   >/dev/null 2>&1 || die "jq not on PATH"
}

vast_api() {
    local method="$1"; shift
    local path="$1"; shift
    local body="${1:-}"
    if [[ -n "$body" ]]; then
        curl -fsS --max-time 30 \
            -X "$method" "${VAST_API_BASE}${path}" \
            -H "Accept: application/json" \
            -H "Authorization: Bearer ${VAST_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$body"
    else
        curl -fsS --max-time 30 \
            -X "$method" "${VAST_API_BASE}${path}" \
            -H "Accept: application/json" \
            -H "Authorization: Bearer ${VAST_API_KEY}"
    fi
}

cmd_create() {
    local type="$1"
    [[ -z "$type" ]] && { err "usage: vast-launcher.sh create <type>"; exit 2; }
    require_api_key

    local query="${VAST_SEARCH_QUERY:-$VAST_SEARCH_QUERY_DEFAULT}"
    log "Searching Vast.ai for available A100 instances..."

    local search_resp
    if ! search_resp="$(vast_api POST /asks/ "$query" 2>&1)"; then
        err "Vast.ai search failed: $search_resp"
        telegram_notify "❌ Vast.ai search failed for ${type}" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
        exit 1
    fi

    local offer_id
    offer_id="$(printf '%s' "$search_resp" | jq -r '.offers[0].id // empty')"
    if [[ -z "$offer_id" ]]; then
        err "No suitable Vast.ai offers found."
        telegram_notify "⚠️ No Vast.ai instances available for ${type}" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
        exit 1
    fi

    log "Renting offer $offer_id ..."
    local rent_body
    rent_body="$(jq -nc --arg img "pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime" \
        '{client_id:"me", image:$img, disk:100, runtype:"ssh"}')"

    local rent_resp
    if ! rent_resp="$(vast_api PUT "/asks/${offer_id}/" "$rent_body" 2>&1)"; then
        err "Vast.ai rent failed: $rent_resp"
        telegram_notify "❌ Vast.ai rent failed for ${type} (offer ${offer_id})" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
        exit 1
    fi

    local instance_id
    instance_id="$(printf '%s' "$rent_resp" | jq -r '.new_contract // .id // empty')"
    if [[ -z "$instance_id" ]]; then
        err "Vast.ai response missing instance id: $rent_resp"
        exit 1
    fi

    printf '%s\n' "$instance_id" > "$(instance_file "$type")"
    log "Vast.ai instance $instance_id provisioned for $type. ID at $(instance_file "$type")."
    telegram_notify "☁️ Vast.ai ${type} instance ${instance_id} provisioning" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
}

cmd_status() {
    local type="$1"
    [[ -z "$type" ]] && { err "usage: vast-launcher.sh status <type>"; exit 2; }
    require_api_key

    local file; file="$(instance_file "$type")"
    if [[ ! -s "$file" ]]; then
        log "No instance recorded for $type."
        exit 0
    fi
    local id; id="$(cat "$file")"
    vast_api GET "/instances/${id}/" || {
        err "Status query failed for instance $id"
        exit 1
    }
}

cmd_destroy() {
    local type="$1"
    [[ -z "$type" ]] && { err "usage: vast-launcher.sh destroy <type>"; exit 2; }
    require_api_key

    local file; file="$(instance_file "$type")"
    if [[ ! -s "$file" ]]; then
        log "No Vast.ai instance recorded for $type — nothing to destroy."
        exit 0
    fi
    local id; id="$(cat "$file")"
    log "Destroying Vast.ai instance $id ..."
    if vast_api DELETE "/instances/${id}/" >/dev/null 2>&1; then
        log "Instance $id destroyed."
        rm -f "$file"
        telegram_notify "🛑 Vast.ai instance ${id} destroyed (${type})" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
        exit 0
    fi
    err "Destroy failed for $id — instance may still be running. Check vast.ai/console."
    telegram_notify "⚠️ Vast.ai destroy failed for ${id} (${type})" "${TELEGRAM_CHAT_ID:-}" "${OP_BOT_TOKEN_REF:-}"
    exit 1
}

main() {
    if [[ $# -lt 2 ]]; then
        err "usage: vast-launcher.sh <create|status|destroy> <workload-type>"
        exit 2
    fi
    load_env_if_present
    local sub="$1"; shift
    case "$sub" in
        create)  cmd_create "$@" ;;
        status)  cmd_status "$@" ;;
        destroy) cmd_destroy "$@" ;;
        *) err "usage: vast-launcher.sh <create|status|destroy> <workload-type>"; exit 2 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
