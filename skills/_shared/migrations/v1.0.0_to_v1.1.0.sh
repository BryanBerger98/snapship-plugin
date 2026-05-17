#!/usr/bin/env bash
# v1.0.0_to_v1.1.0.sh — Enable GitHub native routing (Issue Types + Projects v2
# custom fields) for existing projects that use `tickets.platform = "github"`.
#
# Idempotent. Reads:
#   SNAP_PROJECT_ROOT             (required) repo root
#   SNAP_DECISIONS_JSON           (optional) user decisions JSON
#     {
#       "github_native_routing": "enable" | "skip",
#       "github_project_link":   "auto"   | "skip",
#       "issue_types_map":   { "user-story": "Feature", "bug": "Bug", "epic": "Epic" },
#       "fields_map":        { "priority": { "field_id": "...", "field_name": "...",
#                                            "values": { "must": {"option_id":"...","option_name":"P0"} } },
#                              "size":     { ... }, "scope": { ... } },
#       "project_selection": { "id": "PVT_xxx", "title": "..." }
#     }
#   SNAP_DRY_RUN=true             (optional) print actions only
#
# Steps :
#   1. Skip if tickets.platform != github
#   2. Skip if tickets.github already present (re-run safe)
#   3. Honour decision github_native_routing:
#        skip   → write { "tickets": { "github": { "enabled": false } } } and bump version
#        enable → run detect-github-fields.sh, merge decisions, write tickets.github.*,
#                 bump version
#   4. Bump snapship.config.json.version 1.0(.0) → 1.1
#
# Exit 0 = success (including no-op), 1 = fail.

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
DECISIONS="${SNAP_DECISIONS_JSON:-}"
[ -z "$DECISIONS" ] && DECISIONS='{}'
DRY_RUN="${SNAP_DRY_RUN:-false}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }
echo "$DECISIONS" | jq empty 2>/dev/null || { echo "ERROR: SNAP_DECISIONS_JSON invalid" >&2; exit 1; }

CFG="${PROJECT_ROOT}/snapship.config.json"
say()  { printf '%s\n' "$*"; }
log()  { printf '  %s\n' "$*"; }

say "→ Migration v1.0.0 → v1.1.0"
say "  project_root : ${PROJECT_ROOT}"
say "  dry_run      : ${DRY_RUN}"

# --- 1. Skip if no config ------------------------------------------------
if [ ! -f "$CFG" ]; then
  say "✓ snapship.config.json absent — nothing to migrate."
  exit 0
fi

PLATFORM=$(jq -r '.tickets.platform // ""' "$CFG")
if [ "$PLATFORM" != "github" ]; then
  say "✓ tickets.platform=${PLATFORM:-<absent>} — github-native routing not applicable. Bumping version only."
  if [ "$DRY_RUN" != "true" ]; then
    tmp=$(mktemp)
    jq '.version = "1.1"' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
  fi
  exit 0
fi

# --- 2. Skip if already present ------------------------------------------
HAS_GH=$(jq 'has("tickets") and (.tickets | has("github"))' "$CFG")
if [ "$HAS_GH" = "true" ]; then
  say "✓ tickets.github already present — already migrated. Bumping version only."
  if [ "$DRY_RUN" != "true" ]; then
    tmp=$(mktemp)
    jq '.version = "1.1"' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
  fi
  exit 0
fi

# --- 3. Honour decision --------------------------------------------------
DEC_ROUTING=$(echo "$DECISIONS" | jq -r '.github_native_routing // "enable"')

write_gh_block() {
  local block_json="$1"
  if [ "$DRY_RUN" = "true" ]; then
    say "DRY: would write tickets.github = $block_json"
    return 0
  fi
  local tmp; tmp=$(mktemp)
  jq --argjson gh "$block_json" '
    .tickets = (.tickets // {}) |
    .tickets.github = $gh |
    .version = "1.1"
  ' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
  log "✓ tickets.github written + version → 1.1"
}

if [ "$DEC_ROUTING" = "skip" ]; then
  say "→ Decision = skip — writing tickets.github.enabled=false (opt-out persisted)."
  write_gh_block '{"enabled":false}'
  exit 0
fi

# --- 3b. enable: detect + merge decisions --------------------------------
say "→ Decision = enable — detecting org issue types + projects v2…"

DETECT_OUT="{}"
if [ -x "${SHARED_DIR}/detect-github-fields.sh" ]; then
  if ! DETECT_OUT=$(bash "${SHARED_DIR}/detect-github-fields.sh" --project-root="$PROJECT_ROOT" 2>/dev/null); then
    DETECT_OUT='{"ok":false}'
  fi
fi

DETECT_OK=$(echo "$DETECT_OUT" | jq -r '.ok // false')
if [ "$DETECT_OK" != "true" ]; then
  say "⚠ Detection failed (gh missing or repo not accessible). Writing minimal block; user can re-run via /snap:ticket lazy self-heal."
  write_gh_block '{"enabled":true}'
  exit 0
fi

# Build issue_types map. Prefer SNAP_DECISIONS_JSON.issue_types_map; fall back
# to a heuristic mapping based on detected type names.
ITM=$(echo "$DECISIONS" | jq -c '.issue_types_map // {}')
if [ "$(echo "$ITM" | jq 'length')" = "0" ]; then
  ITM=$(echo "$DETECT_OUT" | jq -c '
    (.issue_types // []) as $types |
    {} as $acc |
    ($acc
      | (if ($types | any(.name=="Feature")) then . + {"user-story":"Feature"} else . end)
      | (if ($types | any(.name=="Bug"))     then . + {"bug":"Bug"} else . end)
      | (if ($types | any(.name=="Epic"))    then . + {"epic":"Epic"} else . end))')
fi

# Project selection: explicit decision wins; otherwise first detected project.
DEC_PROJECT_LINK=$(echo "$DECISIONS" | jq -r '.github_project_link // "auto"')
PROJECT_BLOCK="null"
if [ "$DEC_PROJECT_LINK" != "skip" ]; then
  PROJECT_SEL=$(echo "$DECISIONS" | jq -c '.project_selection // null')
  if [ "$PROJECT_SEL" = "null" ]; then
    PROJECT_SEL=$(echo "$DETECT_OUT" | jq -c '.projects[0] // null')
  fi
  if [ "$PROJECT_SEL" != "null" ]; then
    FIELDS_MAP=$(echo "$DECISIONS" | jq -c '.fields_map // {}')
    PROJECT_BLOCK=$(jq -nc \
      --argjson sel "$PROJECT_SEL" \
      --argjson fmap "$FIELDS_MAP" '
      ($sel | {id, title})
      | . + (if ($fmap | length) > 0 then {fields: $fmap} else {} end)')
  fi
fi

# Compose final block.
GH_BLOCK=$(jq -nc \
  --argjson itm "$ITM" \
  --argjson pj  "$PROJECT_BLOCK" '
  {
    enabled: true,
    issue_types: (if ($itm | length) > 0 then $itm else null end),
    project: $pj,
    label_fallback_prefixes: ["feature:"]
  }
  | with_entries(select(.value != null))')

write_gh_block "$GH_BLOCK"

say ""
say "✅ Migration v1.0.0 → v1.1.0 OK"
say "   GitHub native routing : enabled (or labels-only if user skipped)"
