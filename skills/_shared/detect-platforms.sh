#!/usr/bin/env bash
# detect-platforms.sh — runtime auth check for tickets/docs/wireframes platforms.
#
# Reads config for the configured platform per area, then probes auth state:
#   - github  → `gh auth status`
#   - gitlab  → `glab auth status`
#   - jira    → MCP server `jira` (or `atlassian`) connected
#   - affine  → MCP server `affine` connected
#   - notion  → MCP server `notion` connected (or NOTION_TOKEN env)
#   - frame0  → MCP server `frame0` connected
#
# Output JSON:
#   {
#     "tickets":       {"platform": "...", "ok": true|false, "method": "cli|mcp|env", "detail": "..."},
#     "documentation": {...},
#     "wireframes":    {...},
#     "ok": true|false   // overall (all configured platforms authenticated)
#   }
#
# Exit codes:
#   0  ok (default — auth state reported, no failure)
#   1  bad args
#   2  --strict and at least one configured platform not authenticated
#
# Test hooks:
#   --mock-cli=gh:true,glab:false   force CLI auth probe results
#   $SNAP_MCP_AVAILABLE=name1,…  controls MCP detection (also via --available)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
STRICT="false"
MOCK_CLI=""
AVAILABLE_CSV="${SNAP_MCP_AVAILABLE:-}"
TICKETS_OVERRIDE=""
DOCS_OVERRIDE=""
WIRE_OVERRIDE=""

usage() {
  cat <<EOF
Usage: detect-platforms.sh [OPTIONS]

Probes runtime auth for configured platforms (tickets/docs/wireframes).

Options:
  --project-root=PATH        Project root (default: \$PWD)
  --strict                   Exit 2 when any platform not authenticated
  --available=CSV            Override MCP detection (test hook)
  --mock-cli=NAME:true|false[,…]   Force CLI auth result (e.g., gh:true)
  --tickets=PLATFORM         Override tickets platform (skip config read)
  --docs=PLATFORM            Override documentation platform
  --wireframes=PLATFORM      Override wireframes platform
  -h, --help                 Show this help

Exit codes: 0=ok, 1=bad args, 2=strict + missing auth.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}" ;;
    --strict)          STRICT="true" ;;
    --available=*)     AVAILABLE_CSV="${1#--available=}" ;;
    --mock-cli=*)      MOCK_CLI="${1#--mock-cli=}" ;;
    --tickets=*)       TICKETS_OVERRIDE="${1#--tickets=}" ;;
    --docs=*)          DOCS_OVERRIDE="${1#--docs=}" ;;
    --wireframes=*)    WIRE_OVERRIDE="${1#--wireframes=}" ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

# Resolve config if any override missing
TICKETS_PLATFORM=""
DOCS_PLATFORM=""
WIRE_PLATFORM=""

if [ -z "$TICKETS_OVERRIDE" ] || [ -z "$DOCS_OVERRIDE" ] || [ -z "$WIRE_OVERRIDE" ]; then
  if [ -x "${SCRIPT_DIR}/load-config.sh" ] && [ -f "${PROJECT_ROOT}/snap.config.json" ]; then
    CFG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
    TICKETS_PLATFORM=$(echo "$CFG" | jq -r '.tickets.platform // ""')
    DOCS_PLATFORM=$(echo "$CFG"    | jq -r '.documentation.platform // ""')
    WIRE_PLATFORM=$(echo "$CFG"    | jq -r '.wireframes.platform // ""')
  fi
fi

[ -n "$TICKETS_OVERRIDE" ] && TICKETS_PLATFORM="$TICKETS_OVERRIDE"
[ -n "$DOCS_OVERRIDE" ]    && DOCS_PLATFORM="$DOCS_OVERRIDE"
[ -n "$WIRE_OVERRIDE" ]    && WIRE_PLATFORM="$WIRE_OVERRIDE"

# Lookup mock-cli result for a given binary name; echoes "" if no override.
mock_cli_result() {
  local bin="$1"
  [ -z "$MOCK_CLI" ] && { echo ""; return 0; }
  local entry
  IFS=',' read -ra entries <<< "$MOCK_CLI"
  for entry in "${entries[@]}"; do
    case "$entry" in
      "${bin}:true")  echo "true";  return 0 ;;
      "${bin}:false") echo "false"; return 0 ;;
    esac
  done
  echo ""
}

# Check MCP availability against AVAILABLE_CSV (any of the candidates suffices)
mcp_present() {
  [ -z "$AVAILABLE_CSV" ] && { echo "false"; return 0; }
  local cand
  for cand in "$@"; do
    case ",${AVAILABLE_CSV}," in
      *",${cand},"*) echo "true"; return 0 ;;
    esac
  done
  echo "false"
}

# Probe a CLI tool's auth (returns "true|false|missing" + detail to stderr)
probe_cli_auth() {
  local bin="$1"; shift
  local mock; mock=$(mock_cli_result "$bin")
  if [ -n "$mock" ]; then
    echo "$mock"
    return 0
  fi
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "missing"
    return 0
  fi
  if "$bin" "$@" >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

slot_for_platform() {
  local platform="$1"
  case "$platform" in
    "")
      jq -nc --arg p "" '{platform:$p, ok:false, method:"none", detail:"not configured"}'
      ;;
    github)
      local r; r=$(probe_cli_auth gh auth status)
      case "$r" in
        true)    jq -nc --arg p "$platform" '{platform:$p, ok:true,  method:"cli", detail:"gh authenticated"}' ;;
        false)   jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"cli", detail:"gh present but not authenticated"}' ;;
        missing) jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"cli", detail:"gh CLI not installed"}' ;;
      esac
      ;;
    gitlab)
      local r; r=$(probe_cli_auth glab auth status)
      case "$r" in
        true)    jq -nc --arg p "$platform" '{platform:$p, ok:true,  method:"cli", detail:"glab authenticated"}' ;;
        false)   jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"cli", detail:"glab present but not authenticated"}' ;;
        missing) jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"cli", detail:"glab CLI not installed"}' ;;
      esac
      ;;
    jira)
      local p; p=$(mcp_present jira atlassian)
      if [ "$p" = "true" ]; then
        jq -nc --arg p "$platform" '{platform:$p, ok:true,  method:"mcp", detail:"jira/atlassian MCP available"}'
      else
        jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"mcp", detail:"no jira/atlassian MCP detected"}'
      fi
      ;;
    affine)
      local p; p=$(mcp_present affine)
      if [ "$p" = "true" ]; then
        jq -nc --arg p "$platform" '{platform:$p, ok:true,  method:"mcp", detail:"affine MCP available"}'
      else
        jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"mcp", detail:"affine MCP not detected"}'
      fi
      ;;
    notion)
      local p; p=$(mcp_present notion)
      if [ "$p" = "true" ]; then
        jq -nc --arg p "$platform" '{platform:$p, ok:true,  method:"mcp", detail:"notion MCP available"}'
      elif [ -n "${NOTION_TOKEN:-}" ]; then
        jq -nc --arg p "$platform" '{platform:$p, ok:true,  method:"env", detail:"NOTION_TOKEN set"}'
      else
        jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"mcp", detail:"notion MCP not detected and no NOTION_TOKEN"}'
      fi
      ;;
    frame0)
      local p; p=$(mcp_present frame0)
      if [ "$p" = "true" ]; then
        jq -nc --arg p "$platform" '{platform:$p, ok:true,  method:"mcp", detail:"frame0 MCP available"}'
      else
        jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"mcp", detail:"frame0 MCP not detected"}'
      fi
      ;;
    *)
      jq -nc --arg p "$platform" '{platform:$p, ok:false, method:"unknown", detail:"unsupported platform"}'
      ;;
  esac
}

TICKETS_JSON=$(slot_for_platform "$TICKETS_PLATFORM")
DOCS_JSON=$(slot_for_platform "$DOCS_PLATFORM")
WIRE_JSON=$(slot_for_platform "$WIRE_PLATFORM")

OVERALL=$(jq -nc \
  --argjson t "$TICKETS_JSON" \
  --argjson d "$DOCS_JSON" \
  --argjson w "$WIRE_JSON" '
  # only configured slots count toward overall
  [($t.platform != "" | if . then $t.ok else true end),
   ($d.platform != "" | if . then $d.ok else true end),
   ($w.platform != "" | if . then $w.ok else true end)]
  | all')

jq -nc \
  --argjson t "$TICKETS_JSON" \
  --argjson d "$DOCS_JSON" \
  --argjson w "$WIRE_JSON" \
  --argjson ok "$OVERALL" '
  {tickets: $t, documentation: $d, wireframes: $w, ok: $ok}
'

if [ "$STRICT" = "true" ] && [ "$OVERALL" = "false" ]; then
  exit 2
fi
exit 0
