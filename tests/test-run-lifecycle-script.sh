#!/usr/bin/env bash
# Tests for skills/_shared/run-lifecycle-script.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/run-lifecycle-script.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

mk_project() {
  local dir="$1" hook="$2" path="$3"
  mkdir -p "$dir"
  if [ -n "$hook" ] && [ -n "$path" ]; then
    cat > "$dir/snap.config.json" <<EOF
{ "version": "1.0", "lifecycle_scripts": { "${hook}": "${path}" } }
EOF
  else
    cat > "$dir/snap.config.json" <<'EOF'
{ "version": "1.0" }
EOF
  fi
}

mk_hook_script() {
  local path="$1" body="$2"
  mkdir -p "$(dirname "$path")"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$path"
  chmod +x "$path"
}

echo "=== run-lifecycle-script.sh tests ==="

# 1. Hook configured + script runs ok
echo ""
echo "[1] hook runs"
TMP=$(mktemp -d)
mk_project "$TMP" "pre_develop" "scripts/h.sh"
mk_hook_script "$TMP/scripts/h.sh" 'echo OK'
out=$(bash "$SCRIPT" --hook=pre_develop --project-root="$TMP")
rc=$?
[ $rc -eq 0 ] && ok "1.1 exit 0" || ko "1.1 exit $rc"
[ "$out" = "OK" ] && ok "1.2 stdout passthrough" || ko "1.2 got '$out'"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 2. No hook configured → no-op
echo ""
echo "[2] no hook"
TMP=$(mktemp -d)
mk_project "$TMP" "" ""
out=$(bash "$SCRIPT" --hook=pre_develop --project-root="$TMP" --json)
rc=$?
[ $rc -eq 0 ] && ok "2.1 exit 0" || ko "2.1"
[ "$(echo "$out" | jq -r '.ran')" = "false" ] && ok "2.2 ran=false" || ko "2.2"
[ "$(echo "$out" | jq -r '.reason')" = "no script configured" ] && ok "2.3 reason" || ko "2.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 3. Script fails → forwards exit
echo ""
echo "[3] script fails strict"
TMP=$(mktemp -d)
mk_project "$TMP" "post_develop" "scripts/fail.sh"
mk_hook_script "$TMP/scripts/fail.sh" 'exit 7'
bash "$SCRIPT" --hook=post_develop --project-root="$TMP" >/dev/null 2>&1
rc=$?
[ $rc -eq 7 ] && ok "3.1 forwarded exit 7" || ko "3.1 exit $rc"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 4. --continue-on-error suppresses script failure
echo ""
echo "[4] continue on error"
TMP=$(mktemp -d)
mk_project "$TMP" "post_develop" "scripts/fail.sh"
mk_hook_script "$TMP/scripts/fail.sh" 'exit 7'
out=$(bash "$SCRIPT" --hook=post_develop --project-root="$TMP" --continue-on-error --json)
rc=$?
[ $rc -eq 0 ] && ok "4.1 exit 0" || ko "4.1 exit $rc"
[ "$(echo "$out" | jq -r '.exit_code')" = "7" ] && ok "4.2 exit_code recorded" || ko "4.2"
[ "$(echo "$out" | jq -r '.ran')" = "true" ] && ok "4.3 ran=true" || ko "4.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 5. Script missing on disk
echo ""
echo "[5] script missing"
TMP=$(mktemp -d)
mk_project "$TMP" "pre_qa" "scripts/missing.sh"
bash "$SCRIPT" --hook=pre_qa --project-root="$TMP" >/dev/null 2>&1
rc=$?
[ $rc -eq 3 ] && ok "5.1 exit 3" || ko "5.1 exit $rc"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 6. Missing + --continue-on-error
echo ""
echo "[6] missing + continue"
TMP=$(mktemp -d)
mk_project "$TMP" "pre_qa" "scripts/missing.sh"
out=$(bash "$SCRIPT" --hook=pre_qa --project-root="$TMP" --continue-on-error --json)
rc=$?
[ $rc -eq 0 ] && ok "6.1 exit 0" || ko "6.1"
[ "$(echo "$out" | jq -r '.reason')" = "script missing" ] && ok "6.2 reason" || ko "6.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 7. Script not executable
echo ""
echo "[7] not executable"
TMP=$(mktemp -d)
mk_project "$TMP" "pre_define" "scripts/h.sh"
mkdir -p "$TMP/scripts"
echo '#!/usr/bin/env bash' > "$TMP/scripts/h.sh"
# do NOT chmod +x
bash "$SCRIPT" --hook=pre_define --project-root="$TMP" >/dev/null 2>&1
rc=$?
[ $rc -eq 3 ] && ok "7.1 exit 3" || ko "7.1 exit $rc"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 8. Env vars passed
echo ""
echo "[8] env vars"
TMP=$(mktemp -d)
mk_project "$TMP" "post_ticket" "scripts/env.sh"
mk_hook_script "$TMP/scripts/env.sh" 'echo "$SNAP_HOOK|$SNAP_FEATURE_ID|$SNAP_PROJECT_ROOT"'
out=$(bash "$SCRIPT" --hook=post_ticket --project-root="$TMP" --story-id=05-bar)
[ "$out" = "post_ticket|05-bar|$TMP" ] && ok "8.1 env correct" || ko "8.1 got '$out'"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 9. Absolute path supported
echo ""
echo "[9] absolute path"
TMP=$(mktemp -d)
mk_hook_script "$TMP/abs.sh" 'echo ABS'
cat > "$TMP/snap.config.json" <<EOF
{ "version": "1.0", "lifecycle_scripts": { "pre_wireframe": "${TMP}/abs.sh" } }
EOF
out=$(bash "$SCRIPT" --hook=pre_wireframe --project-root="$TMP")
[ "$out" = "ABS" ] && ok "9.1 abs path runs" || ko "9.1 got '$out'"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 10. Invalid hook name
echo ""
echo "[10] invalid hook"
TMP=$(mktemp -d)
mk_project "$TMP" "" ""
bash "$SCRIPT" --hook=foobar --project-root="$TMP" >/dev/null 2>&1
[ $? -eq 1 ] && ok "10.1 invalid hook rejected" || ko "10.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 11. No config file
echo ""
echo "[11] no config file"
TMP=$(mktemp -d)
out=$(bash "$SCRIPT" --hook=pre_develop --project-root="$TMP" --json)
rc=$?
[ $rc -eq 0 ] && ok "11.1 exit 0 no config" || ko "11.1"
[ "$(echo "$out" | jq -r '.ran')" = "false" ] && ok "11.2 ran=false" || ko "11.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 12. JSON output structure
echo ""
echo "[12] JSON output"
TMP=$(mktemp -d)
mk_project "$TMP" "pre_develop" "scripts/h.sh"
mk_hook_script "$TMP/scripts/h.sh" 'sleep 0.05'
out=$(bash "$SCRIPT" --hook=pre_develop --project-root="$TMP" --json)
[ "$(echo "$out" | jq -r '.hook')" = "pre_develop" ] && ok "12.1 hook field" || ko "12.1"
[ "$(echo "$out" | jq -r '.ran')" = "true" ] && ok "12.2 ran=true" || ko "12.2"
[ "$(echo "$out" | jq -r '.exit_code')" = "0" ] && ok "12.3 exit_code=0" || ko "12.3"
[ "$(echo "$out" | jq 'has("duration_ms")')" = "true" ] && ok "12.4 duration field" || ko "12.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 13. Missing --hook
echo ""
echo "[13] missing --hook"
bash "$SCRIPT" --project-root=/tmp >/dev/null 2>&1
[ $? -eq 1 ] && ok "13.1 exit 1" || ko "13.1"

# 14. All hook names valid
echo ""
echo "[14] all hooks accepted"
TMP=$(mktemp -d)
mk_project "$TMP" "" ""
all_ok=1
for h in pre_define post_define pre_ticket post_ticket pre_wireframe post_wireframe pre_design post_design pre_develop post_develop pre_qa post_qa; do
  bash "$SCRIPT" --hook="$h" --project-root="$TMP" >/dev/null 2>&1 || { all_ok=0; break; }
done
[ $all_ok -eq 1 ] && ok "14.1 all 12 hooks accepted" || ko "14.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"
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
