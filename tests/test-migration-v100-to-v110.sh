#!/usr/bin/env bash
# Tests for skills/_shared/migrations/v1.0.0_to_v1.1.0.sh
# Drives the migration with various SNAP_DECISIONS_JSON values and verifies the
# resulting snapship.config.json shape. detect-github-fields.sh is exercised via
# a stubbed gh binary exported through SNAP_GH_BIN.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/migrations/v1.0.0_to_v1.1.0.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-mig11-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# v1.0 config with github platform (no tickets.github block yet)
seed_v10_github() {
  local dir="$1"
  cat > "${dir}/snapship.config.json" <<'JSON'
{
  "$schema": "./skills/_shared/schemas/config.schema.json",
  "version": "1.0",
  "tickets": { "platform": "github" }
}
JSON
}

seed_v10_jira() {
  local dir="$1"
  cat > "${dir}/snapship.config.json" <<'JSON'
{
  "$schema": "./skills/_shared/schemas/config.schema.json",
  "version": "1.0",
  "tickets": { "platform": "jira" }
}
JSON
}

mk_gh_stub() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
ARGS="$*"
case "$ARGS" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "acme/widgets"; exit 0 ;;
esac
if echo "$ARGS" | grep -q "issueTypes(first:50)"; then
  cat <<'JSON'
{"data":{"repository":{"owner":{"__typename":"Organization","login":"acme"},
 "issueTypes":{"nodes":[{"id":"IT_F","name":"Feature","description":""},
                        {"id":"IT_B","name":"Bug","description":""},
                        {"id":"IT_E","name":"Epic","description":""}]}}}}
JSON
  exit 0
fi
if echo "$ARGS" | grep -q "projectsV2(first:20)"; then
  cat <<'JSON'
{"data":{"repository":{"projectsV2":{"nodes":[
  {"id":"PVT_kwHO1","number":12,"title":"Roadmap","url":"https://github.com/orgs/acme/projects/12",
   "fields":{"nodes":[
     {"__typename":"ProjectV2SingleSelectField","id":"PVTSSF_P","name":"Priority","dataType":"SINGLE_SELECT",
      "options":[{"id":"opt_p0","name":"P0"},{"id":"opt_p1","name":"P1"}]}
   ]}}
]}}}}
JSON
  exit 0
fi
echo "stub: unhandled gh args: $ARGS" >&2; exit 1
STUB
  chmod +x "$path"
}

mk_gh_failing() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
echo "no gh" >&2
exit 1
STUB
  chmod +x "$path"
}

unset SNAP_DECISIONS_JSON SNAP_DRY_RUN SNAP_GH_BIN 2>/dev/null || true

echo "=== migration v1.0.0 → v1.1.0 tests ==="

# 1. No config file → no-op
echo ""
echo "[1] no config — no-op"
DIR=$(setup_dir)
out=$(SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" 2>&1)
rc=$?
[ $rc -eq 0 ] && ok "1.1 exit 0" || ko "1.1 rc=$rc"
echo "$out" | grep -q "nothing to migrate" && ok "1.2 mention absent" || ko "1.2"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"

# 2. Non-github platform → just bump version
echo ""
echo "[2] platform=jira — bump version only"
DIR=$(setup_dir)
seed_v10_jira "$DIR"
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
[ "$(jq -r '.version' "${DIR}/snapship.config.json")" = "1.1" ] && ok "2.1 version 1.1" || ko "2.1"
[ "$(jq 'has("tickets") and (.tickets | has("github"))' "${DIR}/snapship.config.json")" = "false" ] \
  && ok "2.2 no github block added" || ko "2.2"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"

# 3. tickets.github already present → idempotent skip
echo ""
echo "[3] tickets.github already present"
DIR=$(setup_dir)
cat > "${DIR}/snapship.config.json" <<'JSON'
{
  "$schema": "./skills/_shared/schemas/config.schema.json",
  "version": "1.0",
  "tickets": { "platform": "github", "github": { "enabled": false } }
}
JSON
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
[ "$(jq -r '.version' "${DIR}/snapship.config.json")" = "1.1" ] && ok "3.1 version bumped" || ko "3.1"
# Existing github block left untouched
[ "$(jq -r '.tickets.github.enabled' "${DIR}/snapship.config.json")" = "false" ] \
  && ok "3.2 enabled=false preserved" || ko "3.2"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"

# 4. Decision=skip → writes enabled:false, version bumped
echo ""
echo "[4] decision skip — opt-out persisted"
DIR=$(setup_dir)
seed_v10_github "$DIR"
SNAP_PROJECT_ROOT="$DIR" SNAP_DECISIONS_JSON='{"github_native_routing":"skip"}' bash "$SCRIPT" >/dev/null 2>&1
CFG="${DIR}/snapship.config.json"
[ "$(jq -r '.version' "$CFG")" = "1.1" ] && ok "4.1 version" || ko "4.1"
[ "$(jq -r '.tickets.github.enabled' "$CFG")" = "false" ] && ok "4.2 enabled=false" || ko "4.2"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"

# 5. Decision=enable, detection fails → minimal block {enabled:true}
echo ""
echo "[5] decision enable + detection fails → minimal block"
DIR=$(setup_dir)
seed_v10_github "$DIR"
TMPGH=$(mktemp -d)
mk_gh_failing "$TMPGH/gh"
SNAP_PROJECT_ROOT="$DIR" SNAP_GH_BIN="$TMPGH/gh" \
  SNAP_DECISIONS_JSON='{"github_native_routing":"enable"}' bash "$SCRIPT" >/dev/null 2>&1
CFG="${DIR}/snapship.config.json"
[ "$(jq -r '.version' "$CFG")" = "1.1" ] && ok "5.1 version" || ko "5.1"
[ "$(jq -r '.tickets.github.enabled' "$CFG")" = "true" ] && ok "5.2 enabled=true" || ko "5.2"
[ "$(jq 'has("tickets") and (.tickets.github | has("project"))' "$CFG")" = "false" ] \
  && ok "5.3 no project key" || ko "5.3"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"
trash "$TMPGH" 2>/dev/null || rm -rf "$TMPGH"

# 6. Decision=enable + detect succeeds → heuristic issue_types + first project
echo ""
echo "[6] decision enable + detection ok → heuristic + auto project"
DIR=$(setup_dir)
seed_v10_github "$DIR"
TMPGH=$(mktemp -d)
mk_gh_stub "$TMPGH/gh"
SNAP_PROJECT_ROOT="$DIR" SNAP_GH_BIN="$TMPGH/gh" \
  SNAP_DECISIONS_JSON='{"github_native_routing":"enable"}' bash "$SCRIPT" >/dev/null 2>&1
CFG="${DIR}/snapship.config.json"
[ "$(jq -r '.version' "$CFG")" = "1.1" ] && ok "6.1 version" || ko "6.1"
[ "$(jq -r '.tickets.github.enabled' "$CFG")" = "true" ] && ok "6.2 enabled=true" || ko "6.2"
[ "$(jq -r '.tickets.github.issue_types["user-story"]' "$CFG")" = "Feature" ] && ok "6.3 user-story→Feature" || ko "6.3"
[ "$(jq -r '.tickets.github.issue_types.bug' "$CFG")" = "Bug" ] && ok "6.4 bug→Bug" || ko "6.4"
[ "$(jq -r '.tickets.github.issue_types.epic' "$CFG")" = "Epic" ] && ok "6.5 epic→Epic" || ko "6.5"
[ "$(jq -r '.tickets.github.project.id' "$CFG")" = "PVT_kwHO1" ] && ok "6.6 project.id" || ko "6.6"
[ "$(jq -r '.tickets.github.project.number' "$CFG")" = "12" ] && ok "6.7 project.number" || ko "6.7"
[ "$(jq -r '.tickets.github.project.title' "$CFG")" = "Roadmap" ] && ok "6.8 project.title" || ko "6.8"
# No fields_map passed → project should NOT have fields key
[ "$(jq '.tickets.github.project | has("fields")' "$CFG")" = "false" ] && ok "6.9 no fields without map" || ko "6.9"
[ "$(jq -r '.tickets.github.label_fallback_prefixes[0]' "$CFG")" = "feature:" ] && ok "6.10 fallback prefixes" || ko "6.10"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"
trash "$TMPGH" 2>/dev/null || rm -rf "$TMPGH"

# 7. Decision=enable + project_link=skip → no project block
echo ""
echo "[7] github_project_link=skip → no project key"
DIR=$(setup_dir)
seed_v10_github "$DIR"
TMPGH=$(mktemp -d)
mk_gh_stub "$TMPGH/gh"
SNAP_PROJECT_ROOT="$DIR" SNAP_GH_BIN="$TMPGH/gh" \
  SNAP_DECISIONS_JSON='{"github_native_routing":"enable","github_project_link":"skip"}' bash "$SCRIPT" >/dev/null 2>&1
CFG="${DIR}/snapship.config.json"
[ "$(jq -r '.tickets.github.enabled' "$CFG")" = "true" ] && ok "7.1 enabled" || ko "7.1"
[ "$(jq '.tickets.github | has("project")' "$CFG")" = "false" ] && ok "7.2 no project" || ko "7.2"
[ "$(jq -r '.tickets.github.issue_types["user-story"]' "$CFG")" = "Feature" ] && ok "7.3 types still mapped" || ko "7.3"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"
trash "$TMPGH" 2>/dev/null || rm -rf "$TMPGH"

# 8. Decision=enable + explicit issue_types_map + fields_map → both honored
echo ""
echo "[8] explicit issue_types_map + fields_map"
DIR=$(setup_dir)
seed_v10_github "$DIR"
TMPGH=$(mktemp -d)
mk_gh_stub "$TMPGH/gh"
DEC='{
  "github_native_routing":"enable",
  "issue_types_map": { "user-story":"Story", "bug":"Defect" },
  "fields_map": {
    "priority": { "field_id":"PF_pri","field_name":"Priority",
                  "values": { "must": { "option_id":"o_p0","option_name":"P0" } } }
  }
}'
SNAP_PROJECT_ROOT="$DIR" SNAP_GH_BIN="$TMPGH/gh" \
  SNAP_DECISIONS_JSON="$DEC" bash "$SCRIPT" >/dev/null 2>&1
CFG="${DIR}/snapship.config.json"
[ "$(jq -r '.tickets.github.issue_types["user-story"]' "$CFG")" = "Story" ] && ok "8.1 explicit user-story" || ko "8.1"
[ "$(jq -r '.tickets.github.issue_types.bug' "$CFG")" = "Defect" ] && ok "8.2 explicit bug" || ko "8.2"
[ "$(jq -r '.tickets.github.project.fields.priority.field_id' "$CFG")" = "PF_pri" ] && ok "8.3 field_id" || ko "8.3"
[ "$(jq -r '.tickets.github.project.fields.priority.values.must.option_id' "$CFG")" = "o_p0" ] && ok "8.4 option_id" || ko "8.4"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"
trash "$TMPGH" 2>/dev/null || rm -rf "$TMPGH"

# 9. Decision=enable + explicit project_selection wins over auto
echo ""
echo "[9] explicit project_selection beats auto-detected first"
DIR=$(setup_dir)
seed_v10_github "$DIR"
TMPGH=$(mktemp -d)
mk_gh_stub "$TMPGH/gh"
DEC='{
  "github_native_routing":"enable",
  "project_selection": { "id":"PVT_USER","number":99,"url":"https://x","title":"Mine" }
}'
SNAP_PROJECT_ROOT="$DIR" SNAP_GH_BIN="$TMPGH/gh" \
  SNAP_DECISIONS_JSON="$DEC" bash "$SCRIPT" >/dev/null 2>&1
CFG="${DIR}/snapship.config.json"
[ "$(jq -r '.tickets.github.project.id' "$CFG")" = "PVT_USER" ] && ok "9.1 explicit id" || ko "9.1"
[ "$(jq -r '.tickets.github.project.number' "$CFG")" = "99" ] && ok "9.2 explicit number" || ko "9.2"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"
trash "$TMPGH" 2>/dev/null || rm -rf "$TMPGH"

# 10. Invalid SNAP_DECISIONS_JSON → exit 1
echo ""
echo "[10] invalid decisions JSON"
DIR=$(setup_dir)
seed_v10_github "$DIR"
SNAP_PROJECT_ROOT="$DIR" SNAP_DECISIONS_JSON='nope' bash "$SCRIPT" 2>/dev/null
[ $? -eq 1 ] && ok "10.1 exit 1" || ko "10.1"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"

# 11. Dry-run does not modify config
echo ""
echo "[11] dry-run is non-destructive"
DIR=$(setup_dir)
seed_v10_github "$DIR"
BEFORE=$(cat "${DIR}/snapship.config.json")
SNAP_PROJECT_ROOT="$DIR" SNAP_DRY_RUN=true \
  SNAP_DECISIONS_JSON='{"github_native_routing":"skip"}' bash "$SCRIPT" >/dev/null 2>&1
AFTER=$(cat "${DIR}/snapship.config.json")
[ "$BEFORE" = "$AFTER" ] && ok "11.1 file unchanged" || ko "11.1"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"

# 12. Decision default (no SNAP_DECISIONS_JSON) treated as enable
echo ""
echo "[12] default decision = enable"
DIR=$(setup_dir)
seed_v10_github "$DIR"
TMPGH=$(mktemp -d)
mk_gh_stub "$TMPGH/gh"
SNAP_PROJECT_ROOT="$DIR" SNAP_GH_BIN="$TMPGH/gh" bash "$SCRIPT" >/dev/null 2>&1
CFG="${DIR}/snapship.config.json"
[ "$(jq -r '.tickets.github.enabled' "$CFG")" = "true" ] && ok "12.1 enabled true by default" || ko "12.1"
trash "$DIR" 2>/dev/null || rm -rf "$DIR"
trash "$TMPGH" 2>/dev/null || rm -rf "$TMPGH"

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
