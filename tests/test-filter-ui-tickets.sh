#!/usr/bin/env bash
# Tests for skills/_shared/filter-ui-tickets.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/filter-ui-tickets.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — got: $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else ko "$label" "$actual (expected $expected)"; fi
}

DIR=$(mktemp -d -t artysan-flt-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

# 1. Arg validation
echo "[1] arg validation"
set +e
bash "$SCRIPT" 2>/dev/null
RC=$?
set -e
[ "$RC" = "2" ] && ok "1.1 missing --tickets-file → rc=2" || ko "1.1" "rc=$RC"

set +e
bash "$SCRIPT" --tickets-file=/nonexistent.json 2>/dev/null
RC=$?
set -e
[ "$RC" = "1" ] && ok "1.2 missing file → rc=1" || ko "1.2" "rc=$RC"

set +e
echo '{"feature_id":"01-x","platform":"github"}' > "$DIR/no-tickets.json"
bash "$SCRIPT" --tickets-file="$DIR/no-tickets.json" 2>/dev/null
RC=$?
set -e
[ "$RC" = "1" ] && ok "1.3 missing tickets[] → rc=1" || ko "1.3" "rc=$RC"

# 2. File extension heuristic
echo ""
echo "[2] file extensions"
cat > "$DIR/ext.json" <<'JSON'
{
  "feature_id": "01-x",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Build A","status":"todo","files":["src/A.tsx"]},
    {"local_id":"t-002","title":"Build B","status":"todo","files":["src/B.jsx"]},
    {"local_id":"t-003","title":"Build C","status":"todo","files":["src/C.vue"]},
    {"local_id":"t-004","title":"Build D","status":"todo","files":["src/D.svelte"]},
    {"local_id":"t-005","title":"Build E","status":"todo","files":["src/E.astro"]},
    {"local_id":"t-006","title":"Build F","status":"todo","files":["public/F.html"]},
    {"local_id":"t-007","title":"Style","status":"todo","files":["styles/x.css"]},
    {"local_id":"t-008","title":"Style2","status":"todo","files":["styles/x.scss"]},
    {"local_id":"t-009","title":"Backend","status":"todo","files":["api/server.ts"]},
    {"local_id":"t-010","title":"Migration","status":"todo","files":["db/init.sql"]}
  ]
}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/ext.json")
count=$(echo "$out" | jq 'length')
assert_eq "2.1 8 UI by extension (excludes .ts/.sql)" "8" "$count"

ids=$(echo "$out" | jq -r '.[].local_id' | tr '\n' ' ')
echo "$ids" | grep -q "t-009" && ko "2.2 .ts excluded" "$ids" || ok "2.2 .ts excluded"
echo "$ids" | grep -q "t-010" && ko "2.3 .sql excluded" "$ids" || ok "2.3 .sql excluded"

# 3. Path token heuristic
echo ""
echo "[3] path tokens"
cat > "$DIR/path.json" <<'JSON'
{
  "feature_id": "01-x",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"x","status":"todo","files":["components/Foo.ts"]},
    {"local_id":"t-002","title":"x","status":"todo","files":["pages/index.ts"]},
    {"local_id":"t-003","title":"x","status":"todo","files":["app/layout.ts"]},
    {"local_id":"t-004","title":"x","status":"todo","files":["views/Home.ts"]},
    {"local_id":"t-005","title":"x","status":"todo","files":["screens/Login.ts"]},
    {"local_id":"t-006","title":"x","status":"todo","files":["routes/auth.ts"]},
    {"local_id":"t-007","title":"x","status":"todo","files":["src/utils.ts"]}
  ]
}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/path.json")
count=$(echo "$out" | jq 'length')
assert_eq "3.1 6 UI by path token" "6" "$count"

# Each path token surfaced as screen_hint
hint1=$(echo "$out" | jq -r '.[] | select(.local_id=="t-001").screen_hint')
assert_eq "3.2 components hint" "components" "$hint1"

hint5=$(echo "$out" | jq -r '.[] | select(.local_id=="t-005").screen_hint')
assert_eq "3.3 screens hint" "screens" "$hint5"

# 4. Keyword heuristic + screen_hint normalisation
echo ""
echo "[4] keyword matches"
cat > "$DIR/kw.json" <<'JSON'
{
  "feature_id": "01-x",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Signup screen","status":"todo","files":[]},
    {"local_id":"t-002","title":"Add a modal","status":"todo","files":[]},
    {"local_id":"t-003","title":"x","description":"loading state for dashboard","status":"todo","files":[]},
    {"local_id":"t-004","title":"verify page","status":"todo","files":[]},
    {"local_id":"t-005","title":"Database tuning","status":"todo","files":[]}
  ]
}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/kw.json")
count=$(echo "$out" | jq 'length')
assert_eq "4.1 4 UI by keyword (excludes db tuning)" "4" "$count"

h1=$(echo "$out" | jq -r '.[] | select(.local_id=="t-001").screen_hint')
assert_eq "4.2 'signup' → signup-screen" "signup-screen" "$h1"

h2=$(echo "$out" | jq -r '.[] | select(.local_id=="t-002").screen_hint')
assert_eq "4.3 'modal' → modal-section" "modal-section" "$h2"

h3=$(echo "$out" | jq -r '.[] | select(.local_id=="t-003").screen_hint')
# title fails keyword match (single 'x'), description hits 'loading state'
assert_eq "4.4 description match → loading-state-screen" "loading-state-screen" "$h3"

h4=$(echo "$out" | jq -r '.[] | select(.local_id=="t-004").screen_hint')
# 'verify' hits, normalises to verify-screen
assert_eq "4.5 'verify' → verify-screen" "verify-screen" "$h4"

# 5. wireframe_screen pre-set wins
echo ""
echo "[5] wireframe_screen pre-set"
cat > "$DIR/pre.json" <<'JSON'
{
  "feature_id": "01-x",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Already linked","status":"todo","wireframe_screen":"existing-screen","files":["src/utils.ts"]}
  ]
}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/pre.json")
count=$(echo "$out" | jq 'length')
assert_eq "5.1 wireframe_screen forces include" "1" "$count"
hint=$(echo "$out" | jq -r '.[0].screen_hint')
assert_eq "5.2 hint = existing wireframe_screen" "existing-screen" "$hint"

# 6. Empty / non-UI tickets
echo ""
echo "[6] empty result"
cat > "$DIR/empty.json" <<'JSON'
{
  "feature_id": "01-x",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"DB migration","status":"todo","files":["db/init.sql"]},
    {"local_id":"t-002","title":"Refactor parser","status":"todo","files":["src/parser.ts"]}
  ]
}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/empty.json")
count=$(echo "$out" | jq 'length')
assert_eq "6.1 zero UI → empty array" "0" "$count"

echo ""
echo "[7] zero tickets"
cat > "$DIR/zero.json" <<'JSON'
{"feature_id":"01-x","platform":"github","tickets":[]}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/zero.json")
count=$(echo "$out" | jq 'length')
assert_eq "7.1 empty tickets → empty array" "0" "$count"

# 8. case-insensitive keyword
echo ""
echo "[8] case insensitive"
cat > "$DIR/case.json" <<'JSON'
{
  "feature_id": "01-x",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"SIGNUP FORM","status":"todo","files":[]},
    {"local_id":"t-002","title":"NAV bar","status":"todo","files":[]}
  ]
}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/case.json")
count=$(echo "$out" | jq 'length')
assert_eq "8.1 uppercase still matches" "2" "$count"

# 9. Output schema (each entry has required keys only)
echo ""
echo "[9] output schema"
cat > "$DIR/schema.json" <<'JSON'
{
  "feature_id": "01-x",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Signup screen","status":"todo","files":["src/A.tsx"],"description":"long text","priority":"P1"}
  ]
}
JSON
out=$(bash "$SCRIPT" --tickets-file="$DIR/schema.json")
keys=$(echo "$out" | jq -r '.[0] | keys | join(",")')
assert_eq "9.1 only local_id,screen_hint,title returned" "local_id,screen_hint,title" "$keys"

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
