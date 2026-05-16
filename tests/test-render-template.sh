#!/usr/bin/env bash
# Tests for skills/_shared/render-template.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/render-template.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — got: $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else ko "$label" "$actual (expected $expected)"; fi
}

# 1. scalar substitution
echo "[1] scalar substitution"
out=$(echo "Hello {{name}}!" | bash "$SCRIPT" --vars='{"name":"World"}')
assert_eq "1.1 simple var" "Hello World!" "$out"

out=$(echo "{{a}} + {{b}} = {{c}}" | bash "$SCRIPT" --vars='{"a":1,"b":2,"c":3}')
assert_eq "1.2 numeric vars stringified" "1 + 2 = 3" "$out"

# 2. unresolved var without strict → leave as-is
echo ""
echo "[2] unresolved var"
out=$(echo "{{missing}}" | bash "$SCRIPT" --vars='{}')
assert_eq "2.1 leaves placeholder" "{{missing}}" "$out"

# 3. strict mode → exit 3 on unresolved
echo ""
echo "[3] strict mode"
set +e
echo "{{missing}}" | bash "$SCRIPT" --vars='{}' --strict 2>/dev/null
RC=$?
set -e
[ "$RC" = "3" ] && ok "3.1 strict exits 3" || ko "3.1 rc=$RC" "rc=$RC"

# 4. list iteration (scalar)
echo ""
echo "[4] list scalar"
out=$(printf '%s' "{{#xs}}- {{.}}
{{/xs}}" | bash "$SCRIPT" --vars='{"xs":["a","b","c"]}')
# $() strips trailing newlines; compare on the meaningful lines.
expected="- a
- b
- c"
assert_eq "4.1 scalar list" "$expected" "$out"

# 5. list iteration (object)
echo ""
echo "[5] list object"
out=$(printf '%s' "{{#users}}{{name}}={{age}};{{/users}}" \
  | bash "$SCRIPT" --vars='{"users":[{"name":"A","age":30},{"name":"B","age":25}]}')
assert_eq "5.1 object list" "A=30;B=25;" "$out"

# 6. inverted section (empty list)
echo ""
echo "[6] inverted section"
out=$(printf '%s' "{{^items}}none{{/items}}{{#items}}{{.}} {{/items}}" \
  | bash "$SCRIPT" --vars='{"items":[]}')
assert_eq "6.1 empty list → inverted renders" "none" "$out"

out=$(printf '%s' "{{^items}}none{{/items}}{{#items}}{{.}} {{/items}}" \
  | bash "$SCRIPT" --vars='{"items":["x"]}')
assert_eq "6.2 non-empty list → inverted skipped" "x " "$out"

out=$(printf '%s' "{{^missing}}absent{{/missing}}" \
  | bash "$SCRIPT" --vars='{}')
assert_eq "6.3 missing key → inverted renders" "absent" "$out"

# 7. comment stripped
echo ""
echo "[7] comment"
out=$(echo "before{{! this is a comment }}after" | bash "$SCRIPT" --vars='{}')
assert_eq "7.1 comment stripped" "beforeafter" "$out"

# 8. file template + file context
echo ""
echo "[8] file inputs"
DIR=$(mktemp -d -t snap-rdr-XXXXXX)
echo "Hello {{name}}" > "$DIR/tpl.md"
echo '{"name":"File"}' > "$DIR/ctx.json"
out=$(bash "$SCRIPT" --template="$DIR/tpl.md" --context="$DIR/ctx.json")
assert_eq "8.1 file template + context" "Hello File" "$out"
trash "$DIR" 2>/dev/null || true

# 9. mutually exclusive flags
echo ""
echo "[9] arg validation"
set +e
echo "x" | bash "$SCRIPT" --vars='{}' --context=/tmp/x.json 2>/dev/null
RC=$?
set -e
[ "$RC" = "2" ] && ok "9.1 --vars + --context → exit 2" || ko "9.1 rc=$RC" "rc=$RC"

set +e
echo "x" | bash "$SCRIPT" 2>/dev/null
RC=$?
set -e
[ "$RC" = "2" ] && ok "9.2 missing context → exit 2" || ko "9.2 rc=$RC" "rc=$RC"

# 10. & alias renders unescaped scalar
echo ""
echo "[10] & alias"
out=$(echo "{{&raw}}" | bash "$SCRIPT" --vars='{"raw":"<b>x</b>"}')
assert_eq "10.1 {{&var}} renders" "<b>x</b>" "$out"

# 11. nested section
echo ""
echo "[11] nested sections"
out=$(printf '%s' "{{#groups}}[{{name}}: {{#members}}{{.}},{{/members}}]{{/groups}}" \
  | bash "$SCRIPT" --vars='{"groups":[{"name":"A","members":["x","y"]},{"name":"B","members":["z"]}]}')
assert_eq "11.1 nested array of arrays" "[A: x,y,][B: z,]" "$out"

# 12. real PRD template renders cleanly with full context
echo ""
echo "[12] real prd-feature.md template"
DIR=$(mktemp -d -t snap-rdr-XXXXXX)
cat > "$DIR/ctx.json" <<'JSON'
{
  "story_id": "01-auth",
  "feature_title": "Auth",
  "feature_status": "refined",
  "priority": "must",
  "problem_statement": "Users cannot save work",
  "solution_overview": "Email signup",
  "in_scope": "email/password",
  "out_of_scope": "OAuth",
  "lang": "en",
  "acceptance_criteria": [{"ac_id":"1","ac_text":"Signup works"}],
  "wireframes": []
}
JSON
out=$(bash "$SCRIPT" --template="${ROOT}/skills/_shared/templates/docs-defaults/prd-feature.md" --context="$DIR/ctx.json")
echo "$out" | grep -q "Auth" && ok "12.1 prd-feature renders feature_title" || ko "12.1 missing title" "$out"
echo "$out" | grep -q "Signup works" && ok "12.2 renders AC text" || ko "12.2 missing AC" "$out"
trash "$DIR" 2>/dev/null || true

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
