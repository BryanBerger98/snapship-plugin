#!/usr/bin/env bash
# /snap:fetch --probe-tracker connectivity warm-up :
#   - ping tracker via tickets-adapter capabilities
#   - validates capability JSON shape (platform + supports_epic bool)
#   - caches result to .snap/.runtime/tracker-capabilities.json

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

setup_dir() { mktemp -d -t snap-fetch-probe-XXXXXX; }

# Mirror of step-01-fetch.md probe-tracker branch (mode=probe-tracker).
# adapter_cmd is the command that emits the capability JSON (or fails) — tests
# substitute it with a stub.
probe_tracker() {
  local project_root="$1" adapter_cmd="$2"
  local caps_json rc
  cd "$project_root" || return 2
  caps_json=$(eval "$adapter_cmd" 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "ERROR: tracker probe failed" >&2
    return 1
  fi
  if ! jq -e '.platform and (.supports_epic | type == "boolean")' <<<"$caps_json" >/dev/null 2>&1; then
    echo "ERROR: malformed capability payload" >&2
    return 1
  fi
  mkdir -p .snap/.runtime
  printf '%s' "$caps_json" > .snap/.runtime/tracker-capabilities.json
  return 0
}

echo "=== /snap:fetch --probe-tracker connectivity ==="

# 1. Happy path — GitHub-shaped capabilities JSON
DIR=$(setup_dir)
STUB='echo "{\"platform\":\"github\",\"supports_version\":false,\"supports_epic\":true,\"supports_milestone\":true,\"supports_epic_auto_close\":false}"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
[ $? -eq 0 ] && ok "1.1 probe exits 0 on healthy tracker" || ko "1.1" "rc=$?"
F="$DIR/.snap/.runtime/tracker-capabilities.json"
[ -f "$F" ] && ok "1.2 capabilities cached to .snap/.runtime/" || ko "1.2" "missing $F"
[ "$(jq -r '.platform' "$F" 2>/dev/null)" = "github" ] \
  && ok "1.3 cached payload is parseable JSON" || ko "1.3" "payload=$(cat "$F")"
trash "$DIR" 2>/dev/null || true

# 2. Linear-shaped JSON also accepted
DIR=$(setup_dir)
STUB='echo "{\"platform\":\"linear\",\"supports_version\":true,\"supports_epic\":true,\"supports_milestone\":true,\"supports_epic_auto_close\":true}"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1 \
  && ok "2.1 linear capability JSON accepted" || ko "2.1"
trash "$DIR" 2>/dev/null || true

# 3. JIRA-shaped JSON also accepted
DIR=$(setup_dir)
STUB='echo "{\"platform\":\"jira\",\"supports_version\":true,\"supports_epic\":true,\"supports_milestone\":true,\"supports_epic_auto_close\":true}"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1 \
  && ok "3.1 jira capability JSON accepted" || ko "3.1"
trash "$DIR" 2>/dev/null || true

# 4. Idempotent — second call overwrites cache cleanly
DIR=$(setup_dir)
STUB='echo "{\"platform\":\"gitlab\",\"supports_version\":true,\"supports_epic\":true,\"supports_milestone\":true,\"supports_epic_auto_close\":true}"'
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
probe_tracker "$DIR" "$STUB" >/dev/null 2>&1
F="$DIR/.snap/.runtime/tracker-capabilities.json"
[ "$(jq -r '.platform' "$F")" = "gitlab" ] && ok "4.1 second probe overwrites cache" || ko "4.1"
trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
