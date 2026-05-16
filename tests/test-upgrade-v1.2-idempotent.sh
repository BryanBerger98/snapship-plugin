#!/usr/bin/env bash
# v1.1.0_to_v1.2.0.sh — re-running on already-migrated workspace is safe (no-op,
# exit 0). Critical: skill auto-retries cannot corrupt a partially-migrated dir.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/migrations/v1.1.0_to_v1.2.0.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== v1.1.0_to_v1.2.0.sh — idempotence ==="

DIR=$(mktemp -d -t snap-upgrade-idem-XXXXXX)
cat > "$DIR/snapship.config.json" <<'EOF'
{"version":"1.1","project_name":"acme"}
EOF
mkdir -p "$DIR/.snap/features/01-auth"
cat > "$DIR/.snap/features/01-auth/meta.json" <<'EOF'
{"feature_id":"01-auth","story_name":"Auth","state":"defined","created_at":"2026-01-01T00:00:00Z","epic_link":"E1"}
EOF

# First run
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
rc1=$?
[ "$rc1" -eq 0 ] && ok "1.1 first run exits 0" || ko "1.1" "rc=$rc1"

# Snapshot post-first-run
HASH1=$(find "$DIR" -type f -not -path "*/\.*" | sort | xargs cat 2>/dev/null | sha256sum)

# Second run — must be no-op
out=$(SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" 2>&1)
rc2=$?
[ "$rc2" -eq 0 ] && ok "2.1 second run exits 0" || ko "2.1" "rc=$rc2"

HASH2=$(find "$DIR" -type f -not -path "*/\.*" | sort | xargs cat 2>/dev/null | sha256sum)
[ "$HASH1" = "$HASH2" ] && ok "2.2 second run is no-op (content hash stable)" \
  || ko "2.2" "content changed: $HASH1 vs $HASH2"

# Second-run stdout reports "already" / "skip" / version match
echo "$out" | grep -qE "already (present|migrated|applied|absent|absent\.)" \
  && ok "2.3 stdout reports already-migrated state" || ko "2.3" "out=$out"

# Third run with different decision (skip drop_tickets) — still safe
# (no tickets remain; decision should be a no-op since nothing to drop)
SNAP_PROJECT_ROOT="$DIR" \
SNAP_DECISIONS_JSON='{"drop_tickets_cache":"skip"}' \
  bash "$SCRIPT" >/dev/null 2>&1
rc3=$?
[ "$rc3" -eq 0 ] && ok "3.1 third run with skip decision exits 0" || ko "3.1" "rc=$rc3"

# Final state still consistent
VER=$(jq -r '.version' "$DIR/snap.config.json")
[ "$VER" = "1.2" ] && ok "4.1 version still 1.2 post-rerun" || ko "4.1" "got=$VER"
SID=$(jq -r '.story_id' "$DIR/.snap/stories/01-auth/meta.json")
[ "$SID" = "01-auth" ] && ok "4.2 story_id still set post-rerun" || ko "4.2" "got=$SID"

trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
