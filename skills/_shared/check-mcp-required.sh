#!/usr/bin/env bash
# check-mcp-required.sh — validate MCP servers required/optional are available.
#
# Reads required/optional MCP names from explicit args or from config.ai.mcp_servers_*.
# Compares against the list of available MCPs (env-driven for testability, or
# best-effort runtime detection via `claude mcp list` if available).
#
# Outputs JSON:
#   {
#     "ok": true|false,
#     "missing_required": ["..."],
#     "missing_optional": ["..."],
#     "available": ["..."]
#   }
#
# Exit codes:
#   0  all required present (fail-fast satisfied)
#   1  one or more required missing
#   2  bad args
#
# Usage:
#   check-mcp-required.sh --required=affine,frame0 --optional=playwright \
#     --available=affine,frame0,jira
#   check-mcp-required.sh --project-root=/path        # read from config
#   SNAP_MCP_AVAILABLE=affine,frame0 check-mcp-required.sh --required=affine

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
REQUIRED_CSV=""
OPTIONAL_CSV=""
AVAILABLE_CSV="${SNAP_MCP_AVAILABLE:-}"
STRICT_OPTIONAL="false"
USE_CONFIG="auto"   # auto|true|false

usage() {
  cat <<EOF
Usage: check-mcp-required.sh [OPTIONS]

Validates required/optional MCP servers are available.

Options:
  --required=CSV         Required MCP names (comma list)
  --optional=CSV         Optional MCP names (warn if missing)
  --available=CSV        Override runtime MCP detection (test hook)
  --project-root=PATH    Read required/optional from config.ai.mcp_servers_*
                         (default: \$PWD or \$SNAP_PROJECT_ROOT)
  --no-config            Skip config; use only --required/--optional
  --strict-optional      Treat missing optional as failure (exit 1)
  -h, --help             Show this help

Detection priority for available MCPs:
  --available=CSV  >  \$SNAP_MCP_AVAILABLE  >  \`claude mcp list\` (best effort)

Exit codes: 0=ok, 1=missing required, 2=bad args.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --required=*)        REQUIRED_CSV="${1#--required=}" ;;
    --optional=*)        OPTIONAL_CSV="${1#--optional=}" ;;
    --available=*)       AVAILABLE_CSV="${1#--available=}" ;;
    --project-root=*)    PROJECT_ROOT="${1#--project-root=}" ;;
    --no-config)         USE_CONFIG="false" ;;
    --strict-optional)   STRICT_OPTIONAL="true" ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

# Resolve required/optional from config if not provided explicitly
if [ "$USE_CONFIG" != "false" ] && [ -z "$REQUIRED_CSV" ] && [ -z "$OPTIONAL_CSV" ]; then
  if [ -x "${SCRIPT_DIR}/load-config.sh" ] && [ -f "${PROJECT_ROOT}/snapship.config.json" ]; then
    CFG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
    REQUIRED_CSV=$(echo "$CFG" | jq -r '(.ai.mcp_servers_required // []) | join(",")')
    OPTIONAL_CSV=$(echo "$CFG" | jq -r '(.ai.mcp_servers_optional // []) | join(",")')
  fi
fi

# Detect available MCPs if not provided
if [ -z "$AVAILABLE_CSV" ]; then
  if command -v claude >/dev/null 2>&1; then
    # Best-effort: parse `claude mcp list` output. Lines like "name: ..." or "✓ name".
    AVAILABLE_CSV=$(claude mcp list 2>/dev/null \
      | awk '
          /^[[:space:]]*[•✓\*-][[:space:]]*[A-Za-z0-9_-]+/ {
            for (i = 1; i <= NF; i++) if ($i ~ /^[A-Za-z0-9_-]+$/) { print $i; break }
          }
          /^[A-Za-z0-9_-]+:/ { sub(":", "", $1); print $1 }
        ' \
      | paste -sd, - || true)
  fi
fi

csv_to_jsonarray() {
  local csv="$1"
  if [ -z "$csv" ]; then
    echo '[]'
  else
    printf '%s' "$csv" | jq -Rc 'split(",") | map(select(length > 0))'
  fi
}

REQ_JSON=$(csv_to_jsonarray "$REQUIRED_CSV")
OPT_JSON=$(csv_to_jsonarray "$OPTIONAL_CSV")
AVL_JSON=$(csv_to_jsonarray "$AVAILABLE_CSV")

# Compute missing sets
MISSING_REQ=$(jq -nc --argjson req "$REQ_JSON" --argjson avl "$AVL_JSON" '$req - $avl')
MISSING_OPT=$(jq -nc --argjson opt "$OPT_JSON" --argjson avl "$AVL_JSON" '$opt - $avl')

req_missing_count=$(echo "$MISSING_REQ" | jq 'length')
opt_missing_count=$(echo "$MISSING_OPT" | jq 'length')

ok="true"
[ "$req_missing_count" -gt 0 ] && ok="false"
[ "$STRICT_OPTIONAL" = "true" ] && [ "$opt_missing_count" -gt 0 ] && ok="false"

jq -nc \
  --argjson ok_b "$ok" \
  --argjson missing_req "$MISSING_REQ" \
  --argjson missing_opt "$MISSING_OPT" \
  --argjson avl "$AVL_JSON" '
  {
    ok: $ok_b,
    missing_required: $missing_req,
    missing_optional: $missing_opt,
    available: $avl
  }
'

if [ "$ok" = "false" ]; then
  exit 1
fi
exit 0
