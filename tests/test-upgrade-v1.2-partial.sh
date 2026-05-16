#!/usr/bin/env bash
# v1.1.0_to_v1.2.0.sh — partial v1.1 workspace (subset of legacy artefacts).
# Each variant exercises a different absent piece — script must be idempotent
# and graceful (exit 0, only act on what's present).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/migrations/v1.1.0_to_v1.2.0.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== v1.1.0_to_v1.2.0.sh — partial workspaces ==="

# 1. Config-only (no features, no env, no tickets)
DIR=$(mktemp -d -t snap-upgrade-partial-XXXXXX)
cat > "$DIR/snapship.config.json" <<'EOF'
{"version":"1.1","project_name":"x"}
EOF
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "1.1 config-only exits 0" || ko "1.1" "rc=$rc"
[ -f "$DIR/snap.config.json" ] && ok "1.2 config renamed" || ko "1.2" "missing"
VER=$(jq -r '.version' "$DIR/snap.config.json")
[ "$VER" = "1.2" ] && ok "1.3 version bumped" || ko "1.3" "got=$VER"
trash "$DIR" 2>/dev/null || true

# 2. Stories-only (no config — common during partial migration)
DIR=$(mktemp -d -t snap-upgrade-partial-XXXXXX)
mkdir -p "$DIR/.snap/features/03-search"
cat > "$DIR/.snap/features/03-search/meta.json" <<'EOF'
{"feature_id":"03-search","story_name":"Search","state":"defined","created_at":"2026-01-03T00:00:00Z"}
EOF
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "2.1 stories-only exits 0" || ko "2.1" "rc=$rc"
[ -d "$DIR/.snap/stories" ] && ok "2.2 features→stories" || ko "2.2" "missing"
SID=$(jq -r '.story_id' "$DIR/.snap/stories/03-search/meta.json")
[ "$SID" = "03-search" ] && ok "2.3 meta migrated" || ko "2.3" "got=$SID"
trash "$DIR" 2>/dev/null || true

# 3. Env-only
DIR=$(mktemp -d -t snap-upgrade-partial-XXXXXX)
echo "FIGMA_TOKEN=abc" > "$DIR/.env.snapship"
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "3.1 env-only exits 0" || ko "3.1" "rc=$rc"
[ -f "$DIR/.env.snap" ] && ok "3.2 env renamed" || ko "3.2" "missing"
grep -q "FIGMA_TOKEN=abc" "$DIR/.env.snap" && ok "3.3 env content preserved" || ko "3.3" "lost"
trash "$DIR" 2>/dev/null || true

# 4. Rename env decision = skip → .env.snapship preserved
DIR=$(mktemp -d -t snap-upgrade-partial-XXXXXX)
echo "TOKEN=abc" > "$DIR/.env.snapship"
SNAP_PROJECT_ROOT="$DIR" \
SNAP_DECISIONS_JSON='{"rename_env":"skip"}' \
  bash "$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "4.1 skip-env exits 0" || ko "4.1" "rc=$rc"
[ -f "$DIR/.env.snapship" ] && ok "4.2 .env.snapship preserved on skip" || ko "4.2" "missing"
[ ! -f "$DIR/.env.snap" ] && ok "4.3 .env.snap not created on skip" || ko "4.3" "created"
trash "$DIR" 2>/dev/null || true

# 5. drop_tickets_cache = skip → cache kept
DIR=$(mktemp -d -t snap-upgrade-partial-XXXXXX)
mkdir -p "$DIR/.snap/tickets"
echo '{}' > "$DIR/.snap/tickets/01.json"
SNAP_PROJECT_ROOT="$DIR" \
SNAP_DECISIONS_JSON='{"drop_tickets_cache":"skip"}' \
  bash "$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "5.1 skip-tickets exits 0" || ko "5.1" "rc=$rc"
[ -d "$DIR/.snap/tickets" ] && ok "5.2 .snap/tickets/ preserved on skip" || ko "5.2" "trashed"
trash "$DIR" 2>/dev/null || true

# 6. Collision: both snapship.config.json AND snap.config.json present → warn, skip rename
DIR=$(mktemp -d -t snap-upgrade-partial-XXXXXX)
echo '{"version":"1.1"}' > "$DIR/snapship.config.json"
echo '{"version":"1.2","project_name":"new"}' > "$DIR/snap.config.json"
out=$(SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "6.1 collision exits 0 (no abort)" || ko "6.1" "rc=$rc"
echo "$out" | grep -q "Both snapship.config.json AND snap.config.json present" \
  && ok "6.2 collision warning emitted" || ko "6.2" "no warning"
[ -f "$DIR/snapship.config.json" ] && [ -f "$DIR/snap.config.json" ] \
  && ok "6.3 both files preserved" || ko "6.3" "altered"
trash "$DIR" 2>/dev/null || true

# 7. Collision: both .snap/features AND .snap/stories present → abort exit 1
DIR=$(mktemp -d -t snap-upgrade-partial-XXXXXX)
mkdir -p "$DIR/.snap/features/01-x" "$DIR/.snap/stories/01-x"
echo '{}' > "$DIR/.snap/features/01-x/meta.json"
echo '{}' > "$DIR/.snap/stories/01-x/meta.json"
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "7.1 features+stories collision aborts exit 1" || ko "7.1" "rc=$rc"
trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
