#!/usr/bin/env bash
# v1.1.0_to_v1.2.0.sh migration script — full v1.1 workspace.
# Verifies:
#   - snapship.config.json → snap.config.json (content preserved, version bumped)
#   - .env.snapship → .env.snap
#   - .snap/features/ → .snap/stories/
#   - meta.json: feature_id → story_id, epic_link dropped, parent_epic_id null added
#   - .snap/tickets/ trashed by default

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/migrations/v1.1.0_to_v1.2.0.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

setup_v1_1_project() {
  local dir; dir=$(mktemp -d -t snap-upgrade-v12-XXXXXX)
  # config v1.1
  cat > "$dir/snapship.config.json" <<'EOF'
{
  "version": "1.1",
  "project_name": "acme",
  "tickets": {"platform": "github", "github": {"enabled": true}},
  "documentation": {"platform": "affine"}
}
EOF
  # legacy env
  cat > "$dir/.env.snapship" <<'EOF'
FIGMA_TOKEN=xxx
NOTION_TOKEN=yyy
EOF
  # legacy stories dir with meta.json
  mkdir -p "$dir/.snap/features/01-auth"
  cat > "$dir/.snap/features/01-auth/meta.json" <<'EOF'
{
  "feature_id": "01-auth",
  "story_name": "Auth flow",
  "state": "defined",
  "created_at": "2026-01-01T00:00:00Z",
  "epic_link": "AUTH-EPIC-42",
  "lang": "fr"
}
EOF
  mkdir -p "$dir/.snap/features/02-billing"
  cat > "$dir/.snap/features/02-billing/meta.json" <<'EOF'
{
  "feature_id": "02-billing",
  "story_name": "Stripe billing",
  "state": "ticketed",
  "created_at": "2026-01-02T00:00:00Z",
  "lang": "fr"
}
EOF
  # legacy tickets cache
  mkdir -p "$dir/.snap/tickets"
  echo '{"id":"#1","title":"old"}' > "$dir/.snap/tickets/01-auth.json"
  echo "$dir"
}

echo "=== v1.1.0_to_v1.2.0.sh — complete migration ==="

PROJECT=$(setup_v1_1_project)
SNAP_PROJECT_ROOT="$PROJECT" \
SNAP_DECISIONS_JSON='{"drop_tickets_cache":"confirm","rename_env":"auto"}' \
  bash "$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "1.1 migration exits 0" || ko "1.1" "rc=$rc"

# Filesystem renames
[ -f "$PROJECT/snap.config.json" ] && ok "2.1 snap.config.json exists" || ko "2.1" "missing"
[ ! -f "$PROJECT/snapship.config.json" ] && ok "2.2 snapship.config.json gone" || ko "2.2" "still present"
[ -f "$PROJECT/.env.snap" ] && ok "2.3 .env.snap exists" || ko "2.3" "missing"
[ ! -f "$PROJECT/.env.snapship" ] && ok "2.4 .env.snapship gone" || ko "2.4" "still present"
[ -d "$PROJECT/.snap/stories" ] && ok "2.5 .snap/stories/ exists" || ko "2.5" "missing"
[ ! -d "$PROJECT/.snap/features" ] && ok "2.6 .snap/features/ gone" || ko "2.6" "still present"

# Config version bumped
CFG_VER=$(jq -r '.version' "$PROJECT/snap.config.json")
[ "$CFG_VER" = "1.2" ] && ok "3.1 config version = 1.2" || ko "3.1" "got=$CFG_VER"

# Config content preserved (project_name, tickets.platform)
PROJ_NAME=$(jq -r '.project_name' "$PROJECT/snap.config.json")
PLATFORM=$(jq -r '.tickets.platform' "$PROJECT/snap.config.json")
[ "$PROJ_NAME" = "acme" ] && ok "3.2 project_name preserved" || ko "3.2" "got=$PROJ_NAME"
[ "$PLATFORM" = "github" ] && ok "3.3 tickets.platform preserved" || ko "3.3" "got=$PLATFORM"

# meta.json migration: 01-auth (had epic_link)
META1="$PROJECT/.snap/stories/01-auth/meta.json"
SID1=$(jq -r '.story_id' "$META1")
HAS_FID1=$(jq 'has("feature_id")' "$META1")
HAS_EPL1=$(jq 'has("epic_link")' "$META1")
PEID1=$(jq -r '.parent_epic_id' "$META1")
[ "$SID1" = "01-auth" ] && ok "4.1 story_id set" || ko "4.1" "got=$SID1"
[ "$HAS_FID1" = "false" ] && ok "4.2 feature_id removed" || ko "4.2" "still present"
[ "$HAS_EPL1" = "false" ] && ok "4.3 epic_link removed" || ko "4.3" "still present"
[ "$PEID1" = "null" ] && ok "4.4 parent_epic_id = null" || ko "4.4" "got=$PEID1"

# meta.json migration: 02-billing (no epic_link)
META2="$PROJECT/.snap/stories/02-billing/meta.json"
SID2=$(jq -r '.story_id' "$META2")
HAS_EPL2=$(jq 'has("epic_link")' "$META2")
PEID2=$(jq -r '.parent_epic_id' "$META2")
[ "$SID2" = "02-billing" ] && ok "5.1 02-billing story_id set" || ko "5.1" "got=$SID2"
[ "$HAS_EPL2" = "false" ] && ok "5.2 02-billing no epic_link" || ko "5.2" "false-positive"
[ "$PEID2" = "null" ] && ok "5.3 02-billing parent_epic_id null" || ko "5.3" "got=$PEID2"

# tickets cache dropped (trashable systems; absence is the only reliable signal)
[ ! -d "$PROJECT/.snap/tickets" ] && ok "6.1 .snap/tickets/ trashed" || ko "6.1" "still present"

trash "$PROJECT" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
