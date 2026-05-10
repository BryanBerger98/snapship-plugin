#!/usr/bin/env bash
# domains-state.sh — Read/write/validate the domains cache file.
#
# File: .claude/product/domains.json (persistent — survives skill runs)
# Schema: skills/_shared/schemas/domains.schema.json
# Purpose: cache mapping domains + user journeys ↔ doc platform page IDs.
# Source vérité ID for idempotent lookup-or-create in /snap:define publish step
# and /snap:doc-update.
#
# Subcommands:
#   init                          Create empty {} file if missing.
#   add-domain SLUG TITLE PAGE_ID [URL]
#                                 Insert/update domain entry. Idempotent:
#                                 keeps existing journeys.
#   add-journey DOMAIN_SLUG JOURNEY_SLUG TITLE PAGE_ID [URL]
#                                 Insert/update journey under a domain. Domain
#                                 must exist first.
#   get-domain SLUG               Print domain entry (JSON) or empty if missing.
#   get-journey DOMAIN_SLUG JOURNEY_SLUG
#                                 Print journey entry (JSON) or empty.
#   list-domains                  Print domain slugs (one per line).
#   list-journeys [DOMAIN_SLUG]   Print journey slugs (one per line). With arg:
#                                 only journeys of that domain. Without: all,
#                                 prefixed "domain/journey".
#   has-domain SLUG               Exit 0 if present, 1 otherwise.
#   has-journey DOMAIN JOURNEY    Exit 0 if present, 1 otherwise.
#   validate                      Schema check (slug patterns, required fields).
#   path                          Print absolute path to file.
#
# Usage: domains-state.sh <subcommand> [args] [--project-root=PATH]

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"

SLUG_RE='^[a-z0-9][a-z0-9-]*$'

state_file() { echo "${PROJECT_ROOT}/.claude/product/domains.json"; }

usage() {
  cat <<'EOF'
Usage: domains-state.sh <subcommand> [args] [--project-root=PATH]

Subcommands:
  init
  add-domain SLUG TITLE PAGE_ID [URL]
  add-journey DOMAIN_SLUG JOURNEY_SLUG TITLE PAGE_ID [URL]
  get-domain SLUG
  get-journey DOMAIN_SLUG JOURNEY_SLUG
  list-domains
  list-journeys [DOMAIN_SLUG]
  has-domain SLUG
  has-journey DOMAIN_SLUG JOURNEY_SLUG
  validate
  path
  -h, --help
EOF
}

parse_project_root() {
  local out=()
  for a in "$@"; do
    case "$a" in
      --project-root=*) PROJECT_ROOT="${a#--project-root=}" ;;
      *) out+=("$a") ;;
    esac
  done
  if [ "${#out[@]}" -eq 0 ]; then
    REMAINING=()
  else
    REMAINING=("${out[@]}")
  fi
}

ensure_dir() {
  local dir="${PROJECT_ROOT}/.claude/product"
  [ -d "$dir" ] || mkdir -p "$dir"
}

ensure_file() {
  ensure_dir
  local f
  f=$(state_file)
  [ -f "$f" ] || echo '{}' > "$f"
}

check_slug() {
  local slug="$1" label="$2"
  if [[ ! "$slug" =~ $SLUG_RE ]]; then
    echo "ERROR: invalid $label slug '$slug' (must match $SLUG_RE)" >&2
    return 2
  fi
}

cmd_init() {
  ensure_file
}

cmd_add_domain() {
  [ $# -ge 3 ] || { echo "ERROR: add-domain SLUG TITLE PAGE_ID [URL]" >&2; return 2; }
  local slug="$1" title="$2" pid="$3" url="${4:-}"
  check_slug "$slug" "domain"
  [ -n "$pid" ] || { echo "ERROR: PAGE_ID empty" >&2; return 2; }
  ensure_file
  local f tmp now
  f=$(state_file)
  tmp=$(mktemp)
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq \
    --arg slug "$slug" \
    --arg title "$title" \
    --arg pid "$pid" \
    --arg url "$url" \
    --arg now "$now" \
    '
    .[$slug] = (
      (.[$slug] // {journeys: {}, created_at: $now}) +
      {
        title: $title,
        domain_page_id: $pid,
        updated_at: $now
      } +
      (if $url == "" then {} else {domain_url: $url} end)
    )
    | .[$slug].journeys = (.[$slug].journeys // {})
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_add_journey() {
  [ $# -ge 4 ] || { echo "ERROR: add-journey DOMAIN_SLUG JOURNEY_SLUG TITLE PAGE_ID [URL]" >&2; return 2; }
  local dslug="$1" jslug="$2" title="$3" pid="$4" url="${5:-}"
  check_slug "$dslug" "domain"
  check_slug "$jslug" "journey"
  [ -n "$pid" ] || { echo "ERROR: PAGE_ID empty" >&2; return 2; }
  ensure_file
  local f tmp now exists
  f=$(state_file)
  exists=$(jq --arg d "$dslug" 'has($d)' "$f")
  if [ "$exists" != "true" ]; then
    echo "ERROR: domain '$dslug' not found — call add-domain first" >&2
    return 1
  fi
  tmp=$(mktemp)
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq \
    --arg d "$dslug" \
    --arg j "$jslug" \
    --arg title "$title" \
    --arg pid "$pid" \
    --arg url "$url" \
    --arg now "$now" \
    '
    .[$d].journeys[$j] = (
      (.[$d].journeys[$j] // {created_at: $now}) +
      {
        title: $title,
        page_id: $pid,
        updated_at: $now
      } +
      (if $url == "" then {} else {url: $url} end)
    )
    | .[$d].updated_at = $now
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_get_domain() {
  [ $# -eq 1 ] || { echo "ERROR: get-domain SLUG" >&2; return 2; }
  ensure_file
  jq -c --arg s "$1" '.[$s] // empty' "$(state_file)"
}

cmd_get_journey() {
  [ $# -eq 2 ] || { echo "ERROR: get-journey DOMAIN_SLUG JOURNEY_SLUG" >&2; return 2; }
  ensure_file
  jq -c --arg d "$1" --arg j "$2" '.[$d].journeys[$j] // empty' "$(state_file)"
}

cmd_list_domains() {
  ensure_file
  jq -r 'keys[]' "$(state_file)"
}

cmd_list_journeys() {
  ensure_file
  if [ $# -eq 0 ]; then
    jq -r 'to_entries[] | .key as $d | (.value.journeys // {}) | keys[] | "\($d)/\(.)"' "$(state_file)"
  elif [ $# -eq 1 ]; then
    jq -r --arg d "$1" '.[$d].journeys // {} | keys[]' "$(state_file)"
  else
    echo "ERROR: list-journeys [DOMAIN_SLUG]" >&2
    return 2
  fi
}

cmd_has_domain() {
  [ $# -eq 1 ] || { echo "ERROR: has-domain SLUG" >&2; return 2; }
  ensure_file
  local r
  r=$(jq --arg s "$1" 'has($s)' "$(state_file)")
  [ "$r" = "true" ]
}

cmd_has_journey() {
  [ $# -eq 2 ] || { echo "ERROR: has-journey DOMAIN_SLUG JOURNEY_SLUG" >&2; return 2; }
  ensure_file
  local r
  r=$(jq --arg d "$1" --arg j "$2" '.[$d].journeys[$j] != null' "$(state_file)")
  [ "$r" = "true" ]
}

cmd_path() {
  echo "$(state_file)"
}

cmd_validate() {
  ensure_file
  local f errs=()
  f=$(state_file)

  jq empty "$f" 2>/dev/null || { echo "ERROR: invalid JSON" >&2; return 1; }

  while IFS= read -r dslug; do
    [[ "$dslug" =~ $SLUG_RE ]] || errs+=("domain '$dslug': invalid slug")
    local pid
    pid=$(jq -r --arg s "$dslug" '.[$s].domain_page_id // ""' "$f")
    [ -n "$pid" ] || errs+=("domain '$dslug': missing domain_page_id")

    while IFS= read -r jslug; do
      [ -z "$jslug" ] && continue
      [[ "$jslug" =~ $SLUG_RE ]] || errs+=("journey '$dslug/$jslug': invalid slug")
      local jpid jtitle
      jpid=$(jq -r --arg d "$dslug" --arg j "$jslug" '.[$d].journeys[$j].page_id // ""' "$f")
      jtitle=$(jq -r --arg d "$dslug" --arg j "$jslug" '.[$d].journeys[$j].title // ""' "$f")
      [ -n "$jpid" ]   || errs+=("journey '$dslug/$jslug': missing page_id")
      [ -n "$jtitle" ] || errs+=("journey '$dslug/$jslug': missing title")
    done < <(jq -r --arg s "$dslug" '.[$s].journeys // {} | keys[]' "$f")
  done < <(jq -r 'keys[]' "$f")

  if [ "${#errs[@]}" -eq 0 ]; then
    echo "validate: ok" >&2
    return 0
  fi
  printf 'validate: FAIL\n' >&2
  printf '  - %s\n' "${errs[@]}" >&2
  return 1
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
SUBCMD="$1"; shift
parse_project_root "$@"

case "$SUBCMD" in
  init)           cmd_init ;;
  add-domain)     cmd_add_domain     ${REMAINING[@]+"${REMAINING[@]}"} ;;
  add-journey)    cmd_add_journey    ${REMAINING[@]+"${REMAINING[@]}"} ;;
  get-domain)     cmd_get_domain     ${REMAINING[@]+"${REMAINING[@]}"} ;;
  get-journey)    cmd_get_journey    ${REMAINING[@]+"${REMAINING[@]}"} ;;
  list-domains)   cmd_list_domains ;;
  list-journeys)  cmd_list_journeys  ${REMAINING[@]+"${REMAINING[@]}"} ;;
  has-domain)     cmd_has_domain     ${REMAINING[@]+"${REMAINING[@]}"} ;;
  has-journey)    cmd_has_journey    ${REMAINING[@]+"${REMAINING[@]}"} ;;
  validate)       cmd_validate ;;
  path)           cmd_path ;;
  -h|--help)      usage; exit 0 ;;
  *) echo "ERROR: unknown subcommand: $SUBCMD" >&2; usage >&2; exit 2 ;;
esac
