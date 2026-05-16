#!/usr/bin/env bash
# /snap:fetch --probe-tracker auth check :
#   - bad token / unreachable host → exit 1 with explicit message
#   - HTML / error payload → rejected (not silently cached)
#   - missing capability fields → rejected

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

setup_dir() { mktemp -d -t snap-fetch-auth-XXXXXX; }

probe_tracker() {
  local project_root="$1" adapter_cmd="$2"
  local caps_json rc
  cd "$project_root" || return 2
  caps_json=$(eval "$adapter_cmd" 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "ERROR: tracker probe failed — connectivity or auth issue" >&2
    echo "$caps_json" >&2
    return 1
  fi
  if ! jq -e '.platform and (.supports_epic | type == "boolean")' <<<"$caps_json" >/dev/null 2>&1; then
    echo "ERROR: tracker probe returned malformed capability payload" >&2
    echo "$caps_json" >&2
    return 1
  fi
  mkdir -p .snap/.runtime
  printf '%s' "$caps_json" > .snap/.runtime/tracker-capabilities.json
  return 0
}

echo "=== /snap:fetch --probe-tracker auth check ==="

# 1. Adapter exits non-zero (network down / bad token) → probe exits 1
DIR=$(setup_dir)
STUB='echo "401 Unauthorized" >&2; exit 1'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "1.1 adapter failure surfaces exit 1" || ko "1.1" "rc=$rc"
[ ! -f "$DIR/.snap/.runtime/tracker-capabilities.json" ] \
  && ok "1.2 no cache write on failure" \
  || ko "1.2" "cache file should not exist"
trash "$DIR" 2>/dev/null || true

# 2. Stderr explains the failure
DIR=$(setup_dir)
STUB='echo "401 Unauthorized" >&2; exit 1'
stderr=$(probe_tracker "$DIR" "$STUB" 2>&1 >/dev/null)
echo "$stderr" | grep -q "tracker probe failed" \
  && ok "2.1 stderr mentions tracker probe failure" || ko "2.1" "stderr=$stderr"
trash "$DIR" 2>/dev/null || true

# 3. HTML payload (rate-limited login page) rejected
DIR=$(setup_dir)
STUB='echo "<html><body>Please sign in</body></html>"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "3.1 HTML payload rejected" || ko "3.1" "rc=$rc"
[ ! -f "$DIR/.snap/.runtime/tracker-capabilities.json" ] \
  && ok "3.2 no cache write for HTML response" \
  || ko "3.2" "cache file should not exist"
trash "$DIR" 2>/dev/null || true

# 4. JSON missing `platform` field rejected
DIR=$(setup_dir)
STUB='echo "{\"supports_epic\":true}"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "4.1 JSON without platform rejected" || ko "4.1" "rc=$rc"
trash "$DIR" 2>/dev/null || true

# 5. JSON with platform but `supports_epic` not bool rejected
DIR=$(setup_dir)
STUB='echo "{\"platform\":\"github\",\"supports_epic\":\"true\"}"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "5.1 non-bool supports_epic rejected" || ko "5.1" "rc=$rc"
trash "$DIR" 2>/dev/null || true

# 6. Malformed JSON rejected
DIR=$(setup_dir)
STUB='echo "not json at all"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "6.1 unparseable payload rejected" || ko "6.1" "rc=$rc"
trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
