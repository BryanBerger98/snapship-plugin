#!/usr/bin/env bash
# v1.1.0_to_v1.2.0.sh — SNAP_DRY_RUN=true must NOT mutate the filesystem.
# Confirms the script previews actions but leaves everything intact.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/migrations/v1.1.0_to_v1.2.0.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== v1.1.0_to_v1.2.0.sh — dry-run ==="

DIR=$(mktemp -d -t snap-upgrade-dry-XXXXXX)
cat > "$DIR/snapship.config.json" <<'EOF'
{"version":"1.1","project_name":"acme"}
EOF
echo "TOKEN=secret" > "$DIR/.env.snapship"
mkdir -p "$DIR/.snap/features/01-auth" "$DIR/.snap/tickets"
cat > "$DIR/.snap/features/01-auth/meta.json" <<'EOF'
{"feature_id":"01-auth","story_name":"Auth","state":"defined","created_at":"2026-01-01T00:00:00Z","epic_link":"E1"}
EOF
echo '{}' > "$DIR/.snap/tickets/01.json"

out=$(SNAP_PROJECT_ROOT="$DIR" SNAP_DRY_RUN=true bash "$SCRIPT" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "1.1 dry-run exits 0" || ko "1.1" "rc=$rc"
echo "$out" | grep -q "DRY:" && ok "1.2 stdout contains DRY: markers" || ko "1.2" "no DRY"

# Filesystem untouched
[ -f "$DIR/snapship.config.json" ] && ok "2.1 snapship.config.json untouched" || ko "2.1" "removed"
[ ! -f "$DIR/snap.config.json" ] && ok "2.2 snap.config.json NOT created" || ko "2.2" "created"
[ -f "$DIR/.env.snapship" ] && ok "2.3 .env.snapship untouched" || ko "2.3" "removed"
[ ! -f "$DIR/.env.snap" ] && ok "2.4 .env.snap NOT created" || ko "2.4" "created"
[ -d "$DIR/.snap/features" ] && ok "2.5 .snap/features/ untouched" || ko "2.5" "removed"
[ ! -d "$DIR/.snap/stories" ] && ok "2.6 .snap/stories/ NOT created" || ko "2.6" "created"
[ -d "$DIR/.snap/tickets" ] && ok "2.7 .snap/tickets/ untouched" || ko "2.7" "removed"

# meta.json untouched
META="$DIR/.snap/features/01-auth/meta.json"
HAS_FID=$(jq 'has("feature_id")' "$META")
HAS_EPL=$(jq 'has("epic_link")' "$META")
[ "$HAS_FID" = "true" ] && ok "3.1 feature_id untouched" || ko "3.1" "altered"
[ "$HAS_EPL" = "true" ] && ok "3.2 epic_link untouched" || ko "3.2" "altered"

# Config version untouched (still 1.1)
VER=$(jq -r '.version' "$DIR/snapship.config.json")
[ "$VER" = "1.1" ] && ok "4.1 config version untouched" || ko "4.1" "got=$VER"

trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
