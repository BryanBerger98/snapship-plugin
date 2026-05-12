#!/usr/bin/env bash
# Tests for skills/_shared/design-mode-resolver.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/design-mode-resolver.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else ko "$label" "got '$actual' expected '$expected'"; fi
}

TMP=$(mktemp -d)
cleanup() { [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }; }
trap cleanup EXIT

echo "=== design-mode-resolver.sh ==="
echo ""

# --- Fixture setup -------------------------------------------------------
mkdir -p "$TMP/specs"
cat > "$TMP/specs/atomic.yaml" <<'YAML'
version: 1
level: atomic
components: []
YAML

mkdir -p "$TMP/.claude/product/features/01-auth"
cat > "$TMP/.claude/product/features/01-auth/tickets.json" <<'JSON'
{
  "feature_id": "01-auth",
  "tickets": [
    {"local_id":"t-001","title":"Signup screen","files":["src/components/Signup.tsx"]},
    {"local_id":"t-002","title":"DB migration","files":["db/001-users.sql"]}
  ]
}
JSON

mkdir -p "$TMP/.claude/product/features/02-empty"
cat > "$TMP/.claude/product/features/02-empty/tickets.json" <<'JSON'
{"feature_id":"02-empty","tickets":[{"local_id":"t-100","title":"Refactor backend","files":["server/db.py"]}]}
JSON

# === 1. ds-init signal ===================================================
echo "[1] ds-init"
m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=false --specs-dir=specs)
assert_eq "1.1 ds-init when no binding + specs present" "ds-init" "$m"

m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true --specs-dir=specs)
assert_eq "1.2 not ds-init when binding set" "none" "$m"

m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=false --specs-dir=nonexistent)
assert_eq "1.3 not ds-init when specs dir missing" "none" "$m"

# === 2. ds-update signal =================================================
echo "[2] ds-update"
cache_path="$TMP/.design-cache.json"
echo '{"specs_hash":"OLD_HASH_DOES_NOT_MATCH"}' > "$cache_path"

m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --specs-dir=specs --cache-file=.design-cache.json)
assert_eq "2.1 ds-update when hash changed" "ds-update" "$m"

curr_hash=$(cat "$TMP/specs/atomic.yaml" | shasum -a 256 | awk '{print $1}')
jq --arg h "$curr_hash" '.specs_hash=$h' "$cache_path" > "$cache_path.tmp" && mv "$cache_path.tmp" "$cache_path"
m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --specs-dir=specs --cache-file=.design-cache.json)
assert_eq "2.2 not ds-update when hash matches" "none" "$m"

m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --specs-dir=specs --cache-file=missing.json)
assert_eq "2.3 not ds-update when cache file missing" "none" "$m"

# === 3. mockup signal ====================================================
echo "[3] mockup"
m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --cache-file=.design-cache.json --specs-dir=specs \
    --feature-id=01-auth)
# Cache hash matches → ds-update silent, mockup wins.
assert_eq "3.1 mockup when feature has UI tickets" "mockup" "$m"

m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --cache-file=.design-cache.json --specs-dir=specs \
    --feature-id=02-empty)
assert_eq "3.2 not mockup when feature has no UI tickets" "none" "$m"

m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --cache-file=.design-cache.json --specs-dir=specs \
    --feature-id=99-missing)
assert_eq "3.3 not mockup when tickets.json missing" "none" "$m"

# === 4. ambiguous ========================================================
echo "[4] ambiguous (multiple signals)"
# Restore stale cache → ds-update fires, plus mockup fires.
echo '{"specs_hash":"STALE"}' > "$cache_path"
m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --specs-dir=specs --cache-file=.design-cache.json \
    --feature-id=01-auth)
assert_eq "4.1 ambiguous when ds-update + mockup both fire" "ambiguous" "$m"

# Binding empty + specs present + feature UI tickets → ds-init + mockup
m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=false \
    --specs-dir=specs --cache-file=.design-cache.json \
    --feature-id=01-auth)
assert_eq "4.2 ambiguous when ds-init + mockup both fire" "ambiguous" "$m"

# === 5. UI-keyword detection in mockup signal ============================
echo "[5] UI keyword filters"
mkdir -p "$TMP/.claude/product/features/03-kw"
cat > "$TMP/.claude/product/features/03-kw/tickets.json" <<'JSON'
{
  "feature_id":"03-kw",
  "tickets":[
    {"local_id":"t-200","title":"Build settings modal","files":["lib/settings.py"]}
  ]
}
JSON
m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --cache-file=.design-cache.json --specs-dir=specs \
    --feature-id=03-kw)
echo '{"specs_hash":"'"$(cat "$TMP/specs/atomic.yaml" | shasum -a 256 | awk '{print $1}')"'"}' > "$cache_path"
m=$(bash "$SCRIPT" --project-root="$TMP" --ds-binding-set=true \
    --cache-file=.design-cache.json --specs-dir=specs \
    --feature-id=03-kw)
assert_eq "5.1 mockup via title keyword 'modal'" "mockup" "$m"

# === 6. error handling ===================================================
echo "[6] error handling"
out=$(bash "$SCRIPT" 2>&1)
rc=$?
[ "$rc" -ne 0 ] && ok "6.1 missing --project-root exits non-zero" || ko "6.1 missing --project-root exits non-zero" "rc=$rc"
echo "$out" | grep -q "project-root required" && ok "6.2 helpful error message" || ko "6.2 helpful error message" "got: $out"

out=$(bash "$SCRIPT" --project-root="$TMP" --bogus=1 2>&1)
rc=$?
[ "$rc" -eq 2 ] && ok "6.3 unknown arg exits 2" || ko "6.3 unknown arg exits 2" "rc=$rc"

# === Summary =============================================================
echo ""
echo "==============================="
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
