#!/usr/bin/env bash
# taxonomy-state.sh — Read/write/validate .snap/manifests/_taxonomy.json.
#
# Replaces domains-state.sh. Schema v1.0:
#   { schema_version, workspace?, domains? { slug: { page_id, title?, url?,
#     synced_at?, journeys? { slug: { page_id, title?, url?, synced_at? } } } },
#     journeys? { slug: {...} } }
#
# File path: .snap/manifests/_taxonomy.json
# Schema:    skills/_shared/schemas/taxonomy.schema.json
# Source of truth for domain + journey page IDs (idempotent lookup-or-create
# in /snap:define publish and /snap:doc-update).
#
# Subcommands:
#   init                          Bootstrap empty file with schema_version.
#   set-workspace [--platform=P] [--workspace-id=W] [--root-page-id=R]
#                 [--root-url=U]  Update workspace block (merge).
#   get-workspace                 Print workspace JSON or empty.
#   set-vision TEXT               Set workspace.vision (mode=vision).
#   set-principles JSON_ARRAY     Replace workspace.principles (string[]).
#   set-north-star METRIC [CURRENT] [TARGET] [HORIZON]
#                                 Set workspace.north_star (metric required).
#   add-domain SLUG TITLE PAGE_ID [URL]
#   add-journey DOMAIN_SLUG JOURNEY_SLUG TITLE PAGE_ID [URL]
#   add-top-journey SLUG TITLE PAGE_ID [URL]
#                                 Top-level journey (no domain parent).
#   draft-journey DOMAIN_SLUG JOURNEY_SLUG TITLE
#                                 Create journey local-only (state=draft, no page_id).
#                                 DOMAIN_SLUG="_" → top-level journey.
#   set-journey-content DOMAIN_SLUG JOURNEY_SLUG STEPS_JSON OUTCOMES_JSON
#                                 Replace steps[]+outcomes[] of a journey.
#                                 STEPS_JSON: [{title,description?}, ...]
#                                 OUTCOMES_JSON: ["text", ...]
#   get-domain SLUG               JSON or empty.
#   get-journey DOMAIN_SLUG JOURNEY_SLUG
#                                 JSON or empty.
#   list-domains                  Slugs, one per line.
#   list-journeys [DOMAIN_SLUG]   With arg: journeys of that domain. Without:
#                                 "domain/journey" lines (nested + top-level
#                                 marked "_/slug").
#   has-domain SLUG               Exit 0/1.
#   has-journey DOMAIN JOURNEY    Exit 0/1.
#   validate                      Schema check (slug patterns, required fields).
#   path                          Print absolute path to file.
#
# Usage: taxonomy-state.sh <subcommand> [args] [--project-root=PATH]

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
SCHEMA_VERSION="1.1.0"
SLUG_RE='^[a-z0-9][a-z0-9-]*$'

state_file() { echo "${PROJECT_ROOT}/.snap/manifests/_taxonomy.json"; }

usage() {
  cat <<'EOF'
Usage: taxonomy-state.sh <subcommand> [args] [--project-root=PATH]

Subcommands:
  init
  set-workspace [--platform=P] [--workspace-id=W] [--root-page-id=R] [--root-url=U]
  get-workspace
  set-vision TEXT
  set-principles JSON_ARRAY
  set-north-star METRIC [CURRENT] [TARGET] [HORIZON]
  add-domain SLUG TITLE PAGE_ID [URL]
  add-journey DOMAIN_SLUG JOURNEY_SLUG TITLE PAGE_ID [URL]
  add-top-journey SLUG TITLE PAGE_ID [URL]
  draft-journey DOMAIN_SLUG JOURNEY_SLUG TITLE
  set-journey-content DOMAIN_SLUG JOURNEY_SLUG STEPS_JSON OUTCOMES_JSON
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

REMAINING=()
WORKSPACE_PLATFORM=""
WORKSPACE_ID=""
ROOT_PAGE_ID=""
ROOT_URL=""

parse_flags() {
  local out=()
  for a in "$@"; do
    case "$a" in
      --project-root=*)  PROJECT_ROOT="${a#--project-root=}" ;;
      --platform=*)      WORKSPACE_PLATFORM="${a#--platform=}" ;;
      --workspace-id=*)  WORKSPACE_ID="${a#--workspace-id=}" ;;
      --root-page-id=*)  ROOT_PAGE_ID="${a#--root-page-id=}" ;;
      --root-url=*)      ROOT_URL="${a#--root-url=}" ;;
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
  local dir="${PROJECT_ROOT}/.snap/manifests"
  [ -d "$dir" ] || mkdir -p "$dir"
}

ensure_file() {
  ensure_dir
  local f
  f=$(state_file)
  if [ ! -f "$f" ]; then
    jq -n --arg v "$SCHEMA_VERSION" \
      '{schema_version: $v, workspace: {}, domains: {}, journeys: {}}' > "$f"
  fi
}

check_slug() {
  local slug="$1" label="$2"
  if [[ ! "$slug" =~ $SLUG_RE ]]; then
    echo "ERROR: invalid $label slug '$slug' (must match $SLUG_RE)" >&2
    return 2
  fi
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cmd_init() {
  ensure_file
}

cmd_set_workspace() {
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  jq \
    --arg platform "$WORKSPACE_PLATFORM" \
    --arg wid "$WORKSPACE_ID" \
    --arg rpid "$ROOT_PAGE_ID" \
    --arg rurl "$ROOT_URL" \
    --arg now "$now" \
    '
    .workspace = (.workspace // {})
    | (if $platform != "" then .workspace.platform = $platform else . end)
    | (if $wid      != "" then .workspace.workspace_id = $wid else . end)
    | (if $rpid     != "" then .workspace.root_page_id = $rpid else . end)
    | (if $rurl     != "" then .workspace.root_url = $rurl else . end)
    | .workspace.synced_at = $now
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_get_workspace() {
  ensure_file
  jq -c '.workspace // empty' "$(state_file)"
}

cmd_set_vision() {
  [ $# -ge 1 ] || { echo "ERROR: set-vision TEXT" >&2; return 2; }
  local text="$1"
  [ -n "$text" ] || { echo "ERROR: vision empty" >&2; return 2; }
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  jq --arg t "$text" --arg now "$now" '
    .workspace = (.workspace // {})
    | .workspace.vision = $t
    | .workspace.synced_at = $now
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_set_principles() {
  [ $# -ge 1 ] || { echo "ERROR: set-principles JSON_ARRAY" >&2; return 2; }
  local arr="$1"
  echo "$arr" | jq -e 'type == "array"' >/dev/null \
    || { echo "ERROR: principles must be JSON array" >&2; return 2; }
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  jq --argjson p "$arr" --arg now "$now" '
    .workspace = (.workspace // {})
    | .workspace.principles = $p
    | .workspace.synced_at = $now
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_set_north_star() {
  [ $# -ge 1 ] || { echo "ERROR: set-north-star METRIC [CURRENT] [TARGET] [HORIZON]" >&2; return 2; }
  local metric="$1" current="${2:-}" target="${3:-}" horizon="${4:-}"
  [ -n "$metric" ] || { echo "ERROR: METRIC empty" >&2; return 2; }
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  jq --arg m "$metric" --arg c "$current" --arg tg "$target" --arg h "$horizon" --arg now "$now" '
    .workspace = (.workspace // {})
    | .workspace.north_star = (
        {metric: $m}
        + (if $c  == "" then {} else {current: $c}  end)
        + (if $tg == "" then {} else {target:  $tg} end)
        + (if $h  == "" then {} else {horizon: $h}  end)
      )
    | .workspace.synced_at = $now
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_draft_journey() {
  [ $# -ge 3 ] || { echo "ERROR: draft-journey DOMAIN_SLUG JOURNEY_SLUG TITLE" >&2; return 2; }
  local dslug="$1" jslug="$2" title="$3"
  check_slug "$jslug" "journey"
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  if [ "$dslug" = "_" ]; then
    jq --arg j "$jslug" --arg title "$title" --arg now "$now" '
      .journeys = (.journeys // {})
      | .journeys[$j] = (
          (.journeys[$j] // {}) +
          { title: $title, state: "draft", synced_at: $now }
        )
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  else
    check_slug "$dslug" "domain"
    local exists
    exists=$(jq --arg d "$dslug" '(.domains // {}) | has($d)' "$f")
    if [ "$exists" != "true" ]; then
      echo "ERROR: domain '$dslug' not found — call add-domain first" >&2
      rm -f "$tmp"
      return 1
    fi
    jq --arg d "$dslug" --arg j "$jslug" --arg title "$title" --arg now "$now" '
      .domains[$d].journeys = (.domains[$d].journeys // {})
      | .domains[$d].journeys[$j] = (
          (.domains[$d].journeys[$j] // {}) +
          { title: $title, state: "draft", synced_at: $now }
        )
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  fi
}

cmd_set_journey_content() {
  [ $# -ge 4 ] || { echo "ERROR: set-journey-content DOMAIN_SLUG JOURNEY_SLUG STEPS_JSON OUTCOMES_JSON" >&2; return 2; }
  local dslug="$1" jslug="$2" steps="$3" outcomes="$4"
  echo "$steps" | jq -e 'type == "array"' >/dev/null \
    || { echo "ERROR: STEPS_JSON must be array" >&2; return 2; }
  echo "$outcomes" | jq -e 'type == "array"' >/dev/null \
    || { echo "ERROR: OUTCOMES_JSON must be array" >&2; return 2; }
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  if [ "$dslug" = "_" ]; then
    local exists
    exists=$(jq --arg j "$jslug" '(.journeys // {}) | has($j)' "$f")
    if [ "$exists" != "true" ]; then
      echo "ERROR: top-journey '$jslug' not found" >&2
      rm -f "$tmp"
      return 1
    fi
    jq --arg j "$jslug" --argjson s "$steps" --argjson o "$outcomes" --arg now "$now" '
      .journeys[$j].steps = $s
      | .journeys[$j].outcomes = $o
      | .journeys[$j].synced_at = $now
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  else
    local exists
    exists=$(jq --arg d "$dslug" --arg j "$jslug" \
      '((.domains // {})[$d].journeys // {}) | has($j)' "$f")
    if [ "$exists" != "true" ]; then
      echo "ERROR: journey '$dslug/$jslug' not found" >&2
      rm -f "$tmp"
      return 1
    fi
    jq --arg d "$dslug" --arg j "$jslug" --argjson s "$steps" --argjson o "$outcomes" --arg now "$now" '
      .domains[$d].journeys[$j].steps = $s
      | .domains[$d].journeys[$j].outcomes = $o
      | .domains[$d].journeys[$j].synced_at = $now
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  fi
}

cmd_add_domain() {
  [ $# -ge 3 ] || { echo "ERROR: add-domain SLUG TITLE PAGE_ID [URL]" >&2; return 2; }
  local slug="$1" title="$2" pid="$3" url="${4:-}"
  check_slug "$slug" "domain"
  [ -n "$pid" ] || { echo "ERROR: PAGE_ID empty" >&2; return 2; }
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  jq \
    --arg slug "$slug" --arg title "$title" --arg pid "$pid" \
    --arg url "$url" --arg now "$now" \
    '
    .domains = (.domains // {})
    | .domains[$slug] = (
        (.domains[$slug] // {journeys: {}}) +
        { title: $title, page_id: $pid, synced_at: $now } +
        (if $url == "" then {} else {url: $url} end)
      )
    | .domains[$slug].journeys = (.domains[$slug].journeys // {})
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
  exists=$(jq --arg d "$dslug" '(.domains // {}) | has($d)' "$f")
  if [ "$exists" != "true" ]; then
    echo "ERROR: domain '$dslug' not found — call add-domain first" >&2
    return 1
  fi
  tmp=$(mktemp); now=$(now_iso)
  jq \
    --arg d "$dslug" --arg j "$jslug" --arg title "$title" \
    --arg pid "$pid" --arg url "$url" --arg now "$now" \
    '
    .domains[$d].journeys = (.domains[$d].journeys // {})
    | .domains[$d].journeys[$j] = (
        (.domains[$d].journeys[$j] // {}) +
        { title: $title, page_id: $pid, synced_at: $now } +
        (if $url == "" then {} else {url: $url} end)
      )
    | .domains[$d].synced_at = $now
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_add_top_journey() {
  [ $# -ge 3 ] || { echo "ERROR: add-top-journey SLUG TITLE PAGE_ID [URL]" >&2; return 2; }
  local slug="$1" title="$2" pid="$3" url="${4:-}"
  check_slug "$slug" "journey"
  [ -n "$pid" ] || { echo "ERROR: PAGE_ID empty" >&2; return 2; }
  ensure_file
  local f tmp now
  f=$(state_file); tmp=$(mktemp); now=$(now_iso)
  jq \
    --arg slug "$slug" --arg title "$title" --arg pid "$pid" \
    --arg url "$url" --arg now "$now" \
    '
    .journeys = (.journeys // {})
    | .journeys[$slug] = (
        (.journeys[$slug] // {}) +
        { title: $title, page_id: $pid, synced_at: $now } +
        (if $url == "" then {} else {url: $url} end)
      )
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_get_domain() {
  [ $# -eq 1 ] || { echo "ERROR: get-domain SLUG" >&2; return 2; }
  ensure_file
  jq -c --arg s "$1" '(.domains // {})[$s] // empty' "$(state_file)"
}

cmd_get_journey() {
  [ $# -eq 2 ] || { echo "ERROR: get-journey DOMAIN_SLUG JOURNEY_SLUG" >&2; return 2; }
  ensure_file
  # Look first under domain, fallback to top-level if DOMAIN is "_".
  if [ "$1" = "_" ]; then
    jq -c --arg j "$2" '(.journeys // {})[$j] // empty' "$(state_file)"
  else
    jq -c --arg d "$1" --arg j "$2" \
      '((.domains // {})[$d].journeys // {})[$j] // empty' "$(state_file)"
  fi
}

cmd_list_domains() {
  ensure_file
  jq -r '(.domains // {}) | keys[]' "$(state_file)"
}

cmd_list_journeys() {
  ensure_file
  local f
  f=$(state_file)
  if [ $# -eq 0 ]; then
    {
      jq -r '
        (.domains // {}) | to_entries[] |
        .key as $d | (.value.journeys // {}) | keys[] | "\($d)/\(.)"
      ' "$f"
      jq -r '(.journeys // {}) | keys[] | "_/\(.)"' "$f"
    }
  elif [ $# -eq 1 ]; then
    if [ "$1" = "_" ]; then
      jq -r '(.journeys // {}) | keys[]' "$f"
    else
      jq -r --arg d "$1" '((.domains // {})[$d].journeys // {}) | keys[]' "$f"
    fi
  else
    echo "ERROR: list-journeys [DOMAIN_SLUG]" >&2
    return 2
  fi
}

cmd_has_domain() {
  [ $# -eq 1 ] || { echo "ERROR: has-domain SLUG" >&2; return 2; }
  ensure_file
  local r
  r=$(jq --arg s "$1" '(.domains // {}) | has($s)' "$(state_file)")
  [ "$r" = "true" ]
}

cmd_has_journey() {
  [ $# -eq 2 ] || { echo "ERROR: has-journey DOMAIN_SLUG JOURNEY_SLUG" >&2; return 2; }
  ensure_file
  local r
  if [ "$1" = "_" ]; then
    r=$(jq --arg j "$2" '((.journeys // {})[$j]) != null' "$(state_file)")
  else
    r=$(jq --arg d "$1" --arg j "$2" \
      '(((.domains // {})[$d].journeys // {})[$j]) != null' "$(state_file)")
  fi
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

  # schema_version present
  local sv
  sv=$(jq -r '.schema_version // ""' "$f")
  [ -n "$sv" ] || errs+=("missing schema_version")

  while IFS= read -r dslug; do
    [ -z "$dslug" ] && continue
    [[ "$dslug" =~ $SLUG_RE ]] || errs+=("domain '$dslug': invalid slug")
    local pid
    pid=$(jq -r --arg s "$dslug" '.domains[$s].page_id // ""' "$f")
    [ -n "$pid" ] || errs+=("domain '$dslug': missing page_id")

    while IFS= read -r jslug; do
      [ -z "$jslug" ] && continue
      [[ "$jslug" =~ $SLUG_RE ]] || errs+=("journey '$dslug/$jslug': invalid slug")
      local jpid
      jpid=$(jq -r --arg d "$dslug" --arg j "$jslug" \
        '.domains[$d].journeys[$j].page_id // ""' "$f")
      [ -n "$jpid" ] || errs+=("journey '$dslug/$jslug': missing page_id")
    done < <(jq -r --arg s "$dslug" '.domains[$s].journeys // {} | keys[]' "$f")
  done < <(jq -r '.domains // {} | keys[]' "$f")

  while IFS= read -r jslug; do
    [ -z "$jslug" ] && continue
    [[ "$jslug" =~ $SLUG_RE ]] || errs+=("top-journey '$jslug': invalid slug")
    local jpid
    jpid=$(jq -r --arg j "$jslug" '.journeys[$j].page_id // ""' "$f")
    [ -n "$jpid" ] || errs+=("top-journey '$jslug': missing page_id")
  done < <(jq -r '.journeys // {} | keys[]' "$f")

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
parse_flags "$@"

case "$SUBCMD" in
  init)                 cmd_init ;;
  set-workspace)        cmd_set_workspace ;;
  get-workspace)        cmd_get_workspace ;;
  set-vision)           cmd_set_vision           ${REMAINING[@]+"${REMAINING[@]}"} ;;
  set-principles)       cmd_set_principles       ${REMAINING[@]+"${REMAINING[@]}"} ;;
  set-north-star)       cmd_set_north_star       ${REMAINING[@]+"${REMAINING[@]}"} ;;
  add-domain)           cmd_add_domain           ${REMAINING[@]+"${REMAINING[@]}"} ;;
  add-journey)          cmd_add_journey          ${REMAINING[@]+"${REMAINING[@]}"} ;;
  add-top-journey)      cmd_add_top_journey      ${REMAINING[@]+"${REMAINING[@]}"} ;;
  draft-journey)        cmd_draft_journey        ${REMAINING[@]+"${REMAINING[@]}"} ;;
  set-journey-content)  cmd_set_journey_content  ${REMAINING[@]+"${REMAINING[@]}"} ;;
  get-domain)           cmd_get_domain           ${REMAINING[@]+"${REMAINING[@]}"} ;;
  get-journey)          cmd_get_journey          ${REMAINING[@]+"${REMAINING[@]}"} ;;
  list-domains)         cmd_list_domains ;;
  list-journeys)        cmd_list_journeys        ${REMAINING[@]+"${REMAINING[@]}"} ;;
  has-domain)           cmd_has_domain           ${REMAINING[@]+"${REMAINING[@]}"} ;;
  has-journey)          cmd_has_journey          ${REMAINING[@]+"${REMAINING[@]}"} ;;
  validate)             cmd_validate ;;
  path)                 cmd_path ;;
  -h|--help)            usage; exit 0 ;;
  *) echo "ERROR: unknown subcommand: $SUBCMD" >&2; usage >&2; exit 2 ;;
esac
