#!/usr/bin/env bash
# /snap:fetch v1.2 — drops local tickets cache :
#   - sync-fetch.sh refuses --kind=tickets
#   - --probe-tracker writes only to .snap/.runtime/, not .snap/tickets/
#   - sync-fetch.sh staging_target no longer knows tickets

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/sync-fetch.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

setup_dir() { mktemp -d -t snap-fetch-nocache-XXXXXX; }

probe_tracker_writes_runtime_only() {
  local project_root="$1" adapter_cmd="$2"
  local caps_json rc
  cd "$project_root" || return 2
  caps_json=$(eval "$adapter_cmd" 2>&1)
  rc=$?
  [ $rc -ne 0 ] && return 1
  jq -e '.platform and (.supports_epic | type == "boolean")' <<<"$caps_json" >/dev/null 2>&1 || return 1
  mkdir -p .snap/.runtime
  printf '%s' "$caps_json" > .snap/.runtime/tracker-capabilities.json
  return 0
}

echo "=== /snap:fetch — no local tickets cache (v1.2) ==="

# 1. sync-fetch.sh plan --kind=tickets → exit non-zero with explicit message
DIR=$(setup_dir)
mkdir -p "$DIR/.snap/manifests"
cat > "$DIR/.snap/manifests/01-auth.manifest.json" <<'EOF'
{"story_id":"01-auth","refs":{}}
EOF
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" plan --story-id=01-auth --kind=tickets >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "1.1 sync-fetch plan rejects --kind=tickets" || ko "1.1" "rc=$rc"

stderr=$(SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" plan --story-id=01-auth --kind=tickets 2>&1 >/dev/null)
echo "$stderr" | grep -q "removed in v1.2" \
  && ok "1.2 stderr mentions v1.2 removal" || ko "1.2" "stderr=$stderr"
echo "$stderr" | grep -q -- "--probe-tracker" \
  && ok "1.3 stderr hints at --probe-tracker" || ko "1.3" "stderr=$stderr"
trash "$DIR" 2>/dev/null || true

# 2. sync-fetch.sh ack --kind=tickets also rejected
DIR=$(setup_dir)
mkdir -p "$DIR/.snap/manifests"
cat > "$DIR/.snap/manifests/01-auth.manifest.json" <<'EOF'
{"story_id":"01-auth","refs":{}}
EOF
echo "fake" > "$DIR/payload.json"
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" ack --story-id=01-auth --kind=tickets \
  --content-file="$DIR/payload.json" >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "2.1 sync-fetch ack rejects --kind=tickets" || ko "2.1" "rc=$rc"
trash "$DIR" 2>/dev/null || true

# 3. valid kinds still accepted (regression guard — don't kill prd)
DIR=$(setup_dir)
mkdir -p "$DIR/.snap/manifests"
cat > "$DIR/.snap/manifests/01-auth.manifest.json" <<'EOF'
{"story_id":"01-auth","refs":{"prd":{"platform":"notion","page_id":"abc","url":"https://notion.so/abc"}}}
EOF
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" plan --story-id=01-auth --kind=prd >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "3.1 --kind=prd still works" || ko "3.1" "rc=$rc"
trash "$DIR" 2>/dev/null || true

# 4. --probe-tracker writes ONLY to .snap/.runtime/, no .snap/tickets/
DIR=$(setup_dir)
STUB='echo "{\"platform\":\"github\",\"supports_version\":false,\"supports_epic\":true,\"supports_milestone\":true,\"supports_epic_auto_close\":false}"'
probe_tracker_writes_runtime_only "$DIR" "$STUB" >/dev/null 2>&1
[ -f "$DIR/.snap/.runtime/tracker-capabilities.json" ] \
  && ok "4.1 probe writes to .snap/.runtime/" || ko "4.1" "missing runtime cache"
[ ! -d "$DIR/.snap/tickets" ] \
  && ok "4.2 probe does NOT create .snap/tickets/" || ko "4.2" ".snap/tickets/ was created"
trash "$DIR" 2>/dev/null || true

# 5. SKILL.md no longer documents `--kind=tickets` as valid
grep -q "kind=tickets" "${ROOT}/skills/fetch/SKILL.md" \
  && ko "5.1 SKILL.md still mentions --kind=tickets" "expected removed" \
  || ok "5.1 SKILL.md no longer lists --kind=tickets"

# 6. sync-fetch.sh ref_key / staging_target no longer handle tickets
grep -E "^\s*tickets\)\s+echo" "$SCRIPT" \
  && ko "6.1 sync-fetch.sh still has tickets case" "expected removed" \
  || ok "6.1 sync-fetch.sh tickets cases removed from ref_key/staging_target"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
