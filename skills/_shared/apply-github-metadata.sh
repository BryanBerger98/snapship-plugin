#!/usr/bin/env bash
# apply-github-metadata.sh — After a GitHub issue is created, route the story's
# structured attributes (type, priority, size, scope, …) to native GitHub
# primitives (Issue Type + Project v2 single-select fields) per the mapping
# stored in `snap.config.json` under `tickets.github.*`. Returns the residual
# labels that could not be routed natively (caller may apply them with
# `tickets-adapter.sh update --labels=…` as fallback).
#
# Input (JSON on --story-file or stdin):
#   {
#     "type":      "user-story" | "bug" | "epic" | null,
#     "priority":  "must" | "should" | "could" | "P0" | null,
#     "estimated_size": "XS" | "S" | "M" | "L" | "XL" | null,
#     "scope":     "backend" | "frontend" | null,
#     "labels":    ["feature:01-auth", "type:user-story", "priority:must", "scope:backend"]
#   }
#
# Required:
#   --ticket-id=N             GitHub issue number freshly created
#   --project-root=PATH       Project root (default $PWD)
#   --story-file=PATH | -     JSON story (or `-` for stdin)
#
# Optional:
#   --config-json=JSON        Pre-resolved config JSON (skips load-config call)
#   --dry-run                 Forwards SNAP_DRY_RUN=true to the adapter.
#
# Output JSON on stdout:
#   {
#     "ok": true,
#     "ticket_id": "42",
#     "applied": {
#       "issue_type": "Feature" | null,
#       "project_item_id": "PVTI_xxx" | null,
#       "fields": { "priority": "P0", "size": "S", "scope": "Backend" }
#     },
#     "residual_labels": ["feature:01-auth"],
#     "skipped_reasons": { "issue_type": null|"reason", "project": null|"reason" }
#   }
#
# Exit:
#   0 = success (even when nothing is applied — caller handles labels)
#   1 = unrecoverable error (adapter failure on a mapped field)
#   2 = bad args

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
TICKET_ID=""
STORY_FILE=""
CONFIG_JSON=""
DRY_RUN="${SNAP_DRY_RUN:-false}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ticket-id=*)    TICKET_ID="${1#--ticket-id=}" ;;
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --story-file=*)   STORY_FILE="${1#--story-file=}" ;;
    --config-json=*)  CONFIG_JSON="${1#--config-json=}" ;;
    --dry-run)        DRY_RUN="true" ;;
    -h|--help)        sed -n '1,40p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[ -n "$TICKET_ID" ]  || { echo "ERROR: --ticket-id required" >&2; exit 2; }
[ -n "$STORY_FILE" ] || { echo "ERROR: --story-file required" >&2; exit 2; }

if [ "$STORY_FILE" = "-" ]; then
  STORY_JSON=$(cat)
else
  [ -f "$STORY_FILE" ] || { echo "ERROR: story file not found: $STORY_FILE" >&2; exit 2; }
  STORY_JSON=$(cat "$STORY_FILE")
fi
echo "$STORY_JSON" | jq empty 2>/dev/null || { echo "ERROR: story JSON invalid" >&2; exit 2; }

if [ -z "$CONFIG_JSON" ]; then
  if [ -x "${SCRIPT_DIR}/load-config.sh" ]; then
    CONFIG_JSON=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
  else
    CONFIG_JSON='{}'
  fi
fi

ADAPTER="${SCRIPT_DIR}/tickets-adapter.sh"

# --- Extract config-driven mapping ---------------------------------------
GH_CFG=$(echo "$CONFIG_JSON" | jq -c '.tickets.github // {}')
GH_ENABLED=$(echo "$GH_CFG" | jq -r 'if has("enabled") then .enabled else true end')
ISSUE_TYPES_MAP=$(echo "$GH_CFG" | jq -c '.issue_types // {}')
PROJECT_ID=$(echo "$GH_CFG" | jq -r '.project.id // ""')
FIELDS_MAP=$(echo "$GH_CFG" | jq -c '.project.fields // {}')
FALLBACK_PREFIXES=$(echo "$GH_CFG" | jq -c '.label_fallback_prefixes // ["feature:"]')

# --- Extract story attributes --------------------------------------------
STORY_TYPE=$(echo "$STORY_JSON"     | jq -r '.type // ""')
STORY_PRIORITY=$(echo "$STORY_JSON" | jq -r '.priority // ""')
STORY_SIZE=$(echo "$STORY_JSON"     | jq -r '.estimated_size // ""')
STORY_SCOPE=$(echo "$STORY_JSON"    | jq -r '.scope // ""')
STORY_LABELS=$(echo "$STORY_JSON"   | jq -c '.labels // []')

APPLIED_ISSUE_TYPE=""
APPLIED_ITEM_ID=""
APPLIED_FIELDS='{}'
SKIPPED_ISSUE_TYPE="null"
SKIPPED_PROJECT="null"

set_skipped() {
  local key="$1" reason="$2"
  printf '"%s"' "$reason" > /dev/null  # noop, kept for clarity
  if [ "$key" = "issue_type" ]; then SKIPPED_ISSUE_TYPE="\"$reason\""; fi
  if [ "$key" = "project" ];    then SKIPPED_PROJECT="\"$reason\""; fi
}

# Early opt-out: feature disabled → return story as-is, residual = labels.
if [ "$GH_ENABLED" != "true" ]; then
  jq -nc \
    --arg tid "$TICKET_ID" \
    --argjson labels "$STORY_LABELS" '
    {ok:true, ticket_id:$tid,
     applied:{issue_type:null, project_item_id:null, fields:{}},
     residual_labels:$labels,
     skipped_reasons:{issue_type:"disabled", project:"disabled"}}'
  exit 0
fi

# --- 1. Issue Type --------------------------------------------------------
if [ -n "$STORY_TYPE" ]; then
  MAPPED_TYPE=$(echo "$ISSUE_TYPES_MAP" | jq -r --arg t "$STORY_TYPE" '.[$t] // ""')
  if [ -n "$MAPPED_TYPE" ]; then
    SNAP_DRY_RUN="$DRY_RUN" bash "$ADAPTER" \
      --action=set-issue-type \
      --platform=github \
      --project-root="$PROJECT_ROOT" \
      --ticket-id="$TICKET_ID" \
      --issue-type="$MAPPED_TYPE" >/dev/null \
      || { echo "ERROR: set-issue-type failed for $MAPPED_TYPE" >&2; exit 1; }
    APPLIED_ISSUE_TYPE="$MAPPED_TYPE"
  else
    set_skipped "issue_type" "no_mapping_for:$STORY_TYPE"
  fi
else
  set_skipped "issue_type" "no_story_type"
fi

# --- 2. Project v2: add item + apply fields ------------------------------
if [ -n "$PROJECT_ID" ]; then
  ADD_OUT=$(SNAP_DRY_RUN="$DRY_RUN" bash "$ADAPTER" \
    --action=add-to-project \
    --platform=github \
    --project-root="$PROJECT_ROOT" \
    --ticket-id="$TICKET_ID" \
    --project-id="$PROJECT_ID") || { echo "ERROR: add-to-project failed" >&2; exit 1; }
  APPLIED_ITEM_ID=$(echo "$ADD_OUT" | jq -r '.result.item_id // ""')
  [ -n "$APPLIED_ITEM_ID" ] || { echo "ERROR: add-to-project returned no item_id" >&2; exit 1; }

  apply_field() {
    local key="$1" raw_value="$2"
    [ -n "$raw_value" ] || return 0
    local field_id option_id field_name
    field_id=$(echo "$FIELDS_MAP" | jq -r --arg k "$key" '.[$k].field_id // ""')
    [ -n "$field_id" ] || return 0
    option_id=$(echo "$FIELDS_MAP" | jq -r --arg k "$key" --arg v "$raw_value" \
      '.[$k].values[$v].option_id // ""')
    [ -n "$option_id" ] || return 0
    field_name=$(echo "$FIELDS_MAP" | jq -r --arg k "$key" --arg v "$raw_value" \
      '.[$k].values[$v].option_name // $v')
    SNAP_DRY_RUN="$DRY_RUN" bash "$ADAPTER" \
      --action=set-project-field \
      --platform=github \
      --project-root="$PROJECT_ROOT" \
      --item-id="$APPLIED_ITEM_ID" \
      --project-id="$PROJECT_ID" \
      --field-id="$field_id" \
      --option-id="$option_id" >/dev/null \
      || { echo "ERROR: set-project-field $key failed" >&2; exit 1; }
    APPLIED_FIELDS=$(echo "$APPLIED_FIELDS" | jq -c --arg k "$key" --arg v "$field_name" '. + {($k): $v}')
  }

  apply_field "priority" "$STORY_PRIORITY"
  apply_field "size"     "$STORY_SIZE"
  apply_field "scope"    "$STORY_SCOPE"
else
  set_skipped "project" "no_project_configured"
fi

# --- 3. Compute residual labels ------------------------------------------
# Drop labels whose prefix matches a routed-natively concept,
# keep those matching configured `label_fallback_prefixes`.
RESIDUAL=$(jq -nc \
  --argjson labels "$STORY_LABELS" \
  --argjson keep_prefixes "$FALLBACK_PREFIXES" \
  --arg applied_type "$APPLIED_ISSUE_TYPE" \
  --argjson applied_fields "$APPLIED_FIELDS" '
  $labels
  | map(select(. as $l |
      (
        ($keep_prefixes | any(. as $p | $l | startswith($p)))
      ) or (
        # Keep labels not matching the conventional native-routed prefixes
        # AND not duplicates of what we already applied natively.
        ($l | (
          startswith("type:")     or
          startswith("priority:") or
          startswith("scope:")    or
          startswith("size:")
        )) | not
      )
    ))
  | unique')

# --- Emit result ----------------------------------------------------------
jq -nc \
  --arg tid "$TICKET_ID" \
  --arg itype "$APPLIED_ISSUE_TYPE" \
  --arg item  "$APPLIED_ITEM_ID" \
  --argjson fields "$APPLIED_FIELDS" \
  --argjson residual "$RESIDUAL" \
  --argjson skipped_it "$SKIPPED_ISSUE_TYPE" \
  --argjson skipped_pj "$SKIPPED_PROJECT" '
  {
    ok: true,
    ticket_id: $tid,
    applied: {
      issue_type: (if $itype == "" then null else $itype end),
      project_item_id: (if $item == "" then null else $item end),
      fields: $fields
    },
    residual_labels: $residual,
    skipped_reasons: { issue_type: $skipped_it, project: $skipped_pj }
  }'
