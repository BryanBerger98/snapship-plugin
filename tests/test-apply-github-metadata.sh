#!/usr/bin/env bash
# Tests for skills/_shared/apply-github-metadata.sh
#
# Strategy: drive the orchestrator with SNAP_DRY_RUN=true so the underlying
# tickets-adapter.sh calls succeed without hitting `gh`. This lets us assert
# routing decisions + residual_labels computation on pure JSON inputs/outputs.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/apply-github-metadata.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

# Full mapping config matching tests/fixtures/valid/config/github-native-routing.json
FULL_CFG='{
  "tickets": {
    "platform": "github",
    "github": {
      "enabled": true,
      "issue_types": { "user-story": "Feature", "bug": "Bug", "epic": "Epic" },
      "project": {
        "id": "PVT_kwHO12345",
        "number": 12,
        "url": "https://github.com/orgs/acme/projects/12",
        "title": "Roadmap",
        "fields": {
          "priority": {
            "field_id": "PVTSSF_priority",
            "field_name": "Priority",
            "values": {
              "must":   { "option_id": "opt_p0", "option_name": "P0" },
              "should": { "option_id": "opt_p1", "option_name": "P1" },
              "could":  { "option_id": "opt_p2", "option_name": "P2" }
            }
          },
          "size": {
            "field_id": "PVTSSF_size",
            "field_name": "Size",
            "values": {
              "XS": { "option_id": "opt_xs", "option_name": "XS" },
              "S":  { "option_id": "opt_s",  "option_name": "S" },
              "M":  { "option_id": "opt_m",  "option_name": "M" }
            }
          },
          "scope": {
            "field_id": "PVTSSF_scope",
            "field_name": "Scope",
            "values": {
              "backend":  { "option_id": "opt_be", "option_name": "Backend" },
              "frontend": { "option_id": "opt_fe", "option_name": "Frontend" }
            }
          }
        }
      },
      "label_fallback_prefixes": ["feature:", "team:"]
    }
  }
}'

STORY_FULL='{
  "local_id": "t-001",
  "title": "Add signup form",
  "type": "user-story",
  "priority": "must",
  "estimated_size": "S",
  "scope": "backend",
  "labels": ["feature:01-auth", "type:user-story", "priority:must", "scope:backend", "team:core"]
}'

echo "=== apply-github-metadata.sh tests ==="

# --- arg validation -------------------------------------------------------

echo ""
echo "[1] help exits 0"
bash "$SCRIPT" --help >/dev/null 2>&1
[ $? -eq 0 ] && ok "1.1 --help exit 0" || ko "1.1"

echo ""
echo "[2] missing --ticket-id"
bash "$SCRIPT" --story-file=- <<<"{}" 2>/dev/null
[ $? -eq 2 ] && ok "2.1 exit 2" || ko "2.1"

echo ""
echo "[3] missing --story-file"
bash "$SCRIPT" --ticket-id=42 2>/dev/null </dev/null
[ $? -eq 2 ] && ok "3.1 exit 2" || ko "3.1"

echo ""
echo "[4] invalid story JSON"
bash "$SCRIPT" --ticket-id=42 --story-file=- <<<"not json" 2>/dev/null
[ $? -eq 2 ] && ok "4.1 exit 2" || ko "4.1"

# --- disabled opt-out -----------------------------------------------------

echo ""
echo "[5] tickets.github.enabled=false → labels passthrough"
OFF_CFG='{"tickets":{"platform":"github","github":{"enabled":false}}}'
out=$(echo "$STORY_FULL" | bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$OFF_CFG")
rc=$?
[ $rc -eq 0 ] && ok "5.1 exit 0" || ko "5.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "5.2 ok" || ko "5.2"
[ "$(echo "$out" | jq -r '.applied.issue_type // "null"')" = "null" ] && ok "5.3 no issue_type applied" || ko "5.3"
[ "$(echo "$out" | jq -r '.applied.project_item_id // "null"')" = "null" ] && ok "5.4 no project_item_id" || ko "5.4"
[ "$(echo "$out" | jq -r '.residual_labels | length')" = "5" ] && ok "5.5 all labels kept" || ko "5.5"
[ "$(echo "$out" | jq -r '.skipped_reasons.issue_type')" = "disabled" ] && ok "5.6 skip reason" || ko "5.6"

# --- full routing happy path ---------------------------------------------

echo ""
echo "[6] full mapping — type + 3 fields routed natively"
out=$(echo "$STORY_FULL" | SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$FULL_CFG")
rc=$?
[ $rc -eq 0 ] && ok "6.1 exit 0" || ko "6.1 rc=$rc"
[ "$(echo "$out" | jq -r '.applied.issue_type')" = "Feature" ] && ok "6.2 issue_type=Feature" || ko "6.2"
[ "$(echo "$out" | jq -r '.applied.project_item_id')" = "DRY-ITEM-0" ] && ok "6.3 project_item_id from dry-run" || ko "6.3"
[ "$(echo "$out" | jq -r '.applied.fields.priority')" = "P0" ] && ok "6.4 priority=P0" || ko "6.4"
[ "$(echo "$out" | jq -r '.applied.fields.size')" = "S" ] && ok "6.5 size=S" || ko "6.5"
[ "$(echo "$out" | jq -r '.applied.fields.scope')" = "Backend" ] && ok "6.6 scope=Backend" || ko "6.6"

echo ""
echo "[7] residual labels drop type:/priority:/scope:/size:, keep feature: + team:"
residual=$(echo "$out" | jq -c '.residual_labels')
echo "$residual" | jq -e 'index("feature:01-auth")' >/dev/null && ok "7.1 feature: kept" || ko "7.1"
echo "$residual" | jq -e 'index("team:core")'       >/dev/null && ok "7.2 team: kept" || ko "7.2"
echo "$residual" | jq -e 'index("type:user-story") == null' >/dev/null && ok "7.3 type: dropped" || ko "7.3"
echo "$residual" | jq -e 'index("priority:must")  == null'  >/dev/null && ok "7.4 priority: dropped" || ko "7.4"
echo "$residual" | jq -e 'index("scope:backend")  == null'  >/dev/null && ok "7.5 scope: dropped" || ko "7.5"

# --- type without mapping ------------------------------------------------

echo ""
echo "[8] story.type not in issue_types map → skip + reason"
STORY_UNMAPPED='{"local_id":"t-002","title":"x","type":"chore","priority":"must","estimated_size":"S","scope":"backend","labels":[]}'
out=$(echo "$STORY_UNMAPPED" | SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$FULL_CFG")
[ "$(echo "$out" | jq -r '.applied.issue_type // "null"')" = "null" ] && ok "8.1 no issue_type" || ko "8.1"
[ "$(echo "$out" | jq -r '.skipped_reasons.issue_type')" = "no_mapping_for:chore" ] && ok "8.2 reason" || ko "8.2"
# Fields still apply since priority/size/scope mapped
[ "$(echo "$out" | jq -r '.applied.fields.priority')" = "P0" ] && ok "8.3 priority still applied" || ko "8.3"

# --- story without type --------------------------------------------------

echo ""
echo "[9] story without type → skip with no_story_type reason"
STORY_NOTYPE='{"local_id":"t-003","title":"x","priority":"must","estimated_size":"S","scope":"backend","labels":["feature:x"]}'
out=$(echo "$STORY_NOTYPE" | SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$FULL_CFG")
[ "$(echo "$out" | jq -r '.skipped_reasons.issue_type')" = "no_story_type" ] && ok "9.1 reason" || ko "9.1"

# --- no project configured -----------------------------------------------

echo ""
echo "[10] no project.id → skip project, type still routed, all labels except type:/priority:/scope:/size: kept"
NO_PJ_CFG='{"tickets":{"platform":"github","github":{"enabled":true,"issue_types":{"user-story":"Feature"},"label_fallback_prefixes":["feature:"]}}}'
out=$(echo "$STORY_FULL" | SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$NO_PJ_CFG")
[ "$(echo "$out" | jq -r '.applied.issue_type')" = "Feature" ] && ok "10.1 type still routed" || ko "10.1"
[ "$(echo "$out" | jq -r '.applied.project_item_id // "null"')" = "null" ] && ok "10.2 no project_item_id" || ko "10.2"
[ "$(echo "$out" | jq -r '.applied.fields | length')" = "0" ] && ok "10.3 no fields" || ko "10.3"
[ "$(echo "$out" | jq -r '.skipped_reasons.project')" = "no_project_configured" ] && ok "10.4 reason" || ko "10.4"

# --- partial field map ---------------------------------------------------

echo ""
echo "[11] only priority in fields map → size/scope unrouted but project_item_id added"
PARTIAL_CFG='{"tickets":{"platform":"github","github":{"enabled":true,"issue_types":{"user-story":"Feature"},
  "project":{"id":"PVT_X","number":1,"url":"u","title":"t",
    "fields":{"priority":{"field_id":"PF","values":{"must":{"option_id":"po","option_name":"P0"}}}}},
  "label_fallback_prefixes":["feature:"]}}}'
out=$(echo "$STORY_FULL" | SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$PARTIAL_CFG")
[ "$(echo "$out" | jq -r '.applied.project_item_id')" = "DRY-ITEM-0" ] && ok "11.1 added to project" || ko "11.1"
[ "$(echo "$out" | jq -r '.applied.fields.priority')" = "P0" ] && ok "11.2 priority applied" || ko "11.2"
[ "$(echo "$out" | jq -r '.applied.fields.size // "null"')" = "null" ] && ok "11.3 size not applied" || ko "11.3"
[ "$(echo "$out" | jq -r '.applied.fields.scope // "null"')" = "null" ] && ok "11.4 scope not applied" || ko "11.4"

# --- value not in mapping ------------------------------------------------

echo ""
echo "[12] story value missing from values map → field skipped silently"
STORY_BAD_PRIO='{"local_id":"t-x","title":"x","type":"user-story","priority":"P99","estimated_size":"S","scope":"backend","labels":[]}'
out=$(echo "$STORY_BAD_PRIO" | SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$FULL_CFG")
[ "$(echo "$out" | jq -r '.applied.fields.priority // "null"')" = "null" ] && ok "12.1 priority skipped" || ko "12.1"
[ "$(echo "$out" | jq -r '.applied.fields.size')" = "S" ] && ok "12.2 size still works" || ko "12.2"

# --- file input path (not stdin) -----------------------------------------

echo ""
echo "[13] --story-file=PATH reads from disk"
TMP=$(mktemp -d)
echo "$STORY_FULL" > "$TMP/story.json"
out=$(SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file="$TMP/story.json" \
  --config-json="$FULL_CFG")
[ "$(echo "$out" | jq -r '.applied.issue_type')" = "Feature" ] && ok "13.1 from file" || ko "13.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[14] --story-file=PATH that does not exist"
bash "$SCRIPT" --ticket-id=42 --story-file=/nonexistent/path.json 2>/dev/null
[ $? -eq 2 ] && ok "14.1 exit 2" || ko "14.1"

# --- defaults when config absent -----------------------------------------

echo ""
echo "[15] no github config at all → enabled defaults true, fall back to label_fallback_prefixes=[feature:]"
EMPTY_CFG='{}'
out=$(echo "$STORY_FULL" | SNAP_DRY_RUN=true bash "$SCRIPT" \
  --ticket-id=42 --story-file=- \
  --config-json="$EMPTY_CFG")
[ "$(echo "$out" | jq -r '.applied.issue_type // "null"')" = "null" ] && ok "15.1 no mapping → no type" || ko "15.1"
echo "$out" | jq -e '.residual_labels | index("feature:01-auth")' >/dev/null && ok "15.2 feature: kept by default" || ko "15.2"
echo "$out" | jq -e '.residual_labels | index("team:core")' >/dev/null && ok "15.3 unprefixed kept" || ko "15.3"
echo "$out" | jq -e '.residual_labels | index("type:user-story") == null' >/dev/null && ok "15.4 type: still dropped" || ko "15.4"

unset TMP

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Errors:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
