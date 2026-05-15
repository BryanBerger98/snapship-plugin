#!/usr/bin/env bash
# Tests for skills/_shared/sync-fetch.sh
# Usage: bash tests/test-sync-fetch.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/sync-fetch.sh"
SETUP="${ROOT}/skills/_shared/setup-snap-dir.sh"
PUSH="${ROOT}/skills/_shared/sync-push.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-fetch-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# init repo + push a fake remote ref so refs.prd exists in manifest
init_repo_with_ref() {
  local dir="$1"
  bash "$SETUP" --project-root="$dir" --feature-id=01-auth --feature-name="Auth" >/dev/null
  mkdir -p "${dir}/.snap/PRDs" && echo "PRD" > "${dir}/.snap/PRDs/01-auth.md"
  bash "$PUSH" ack --feature-id=01-auth --kind=prd --platform=affine --url=https://example.com/p --page-id=page-1 --project-root="$dir" >/dev/null
}

echo "=== sync-fetch.sh tests ==="

# 1. plan ok when ref exists
echo ""
echo "[1] plan with ref"
DIR=$(setup_dir)
init_repo_with_ref "$DIR"
out=$(bash "$SCRIPT" plan --feature-id=01-auth --kind=prd --project-root="$DIR")
[ "$(echo "$out" | jq -r '.ref_key')" = "prd" ] && ok "1.1 ref_key" || ko "1.1"
[ "$(echo "$out" | jq -r '.ref.page_id')" = "page-1" ] && ok "1.2 ref.page_id passthrough" || ko "1.2"
[ "$(echo "$out" | jq -r '.staging_target')" = "${DIR}/.snap/PRDs/01-auth.md" ] && ok "1.3 staging_target" || ko "1.3"
trash "$DIR" 2>/dev/null || true

# 2. plan fails when ref missing
echo ""
echo "[2] plan no ref"
DIR=$(setup_dir)
bash "$SETUP" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" >/dev/null
if bash "$SCRIPT" plan --feature-id=01-auth --kind=prd --project-root="$DIR" 2>/dev/null; then
  ko "2.1 should fail when refs.prd absent"
else
  ok "2.1 missing ref rejected"
fi
trash "$DIR" 2>/dev/null || true

# 3. plan fails when manifest missing
echo ""
echo "[3] plan no manifest"
DIR=$(setup_dir)
if bash "$SCRIPT" plan --feature-id=01-auth --kind=prd --project-root="$DIR" 2>/dev/null; then
  ko "3.1 should fail"
else
  ok "3.1 missing manifest rejected"
fi
trash "$DIR" 2>/dev/null || true

# 4. ack writes content file to staging target
echo ""
echo "[4] ack"
DIR=$(setup_dir)
init_repo_with_ref "$DIR"
CONTENT=$(mktemp)
echo "REMOTE_PRD" > "$CONTENT"
out=$(bash "$SCRIPT" ack --feature-id=01-auth --kind=prd --content-file="$CONTENT" --project-root="$DIR")
echo "$out" | grep -q "fetch-ack:01-auth:prd:synced" && ok "4.1 stdout" || ko "4.1 got: $out"
[ -f "${DIR}/.snap/PRDs/01-auth.md" ] && ok "4.2 staging written" || ko "4.2"
grep -q "REMOTE_PRD" "${DIR}/.snap/PRDs/01-auth.md" && ok "4.3 content preserved" || ko "4.3"
M="${DIR}/.snap/manifests/01-auth.manifest.json"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "synced" ] && ok "4.4 sync_status synced" || ko "4.4"
trash "$CONTENT" 2>/dev/null || true
trash "$DIR" 2>/dev/null || true

# 5. ack requires content-file
echo ""
echo "[5] ack requires content"
DIR=$(setup_dir)
init_repo_with_ref "$DIR"
if bash "$SCRIPT" ack --feature-id=01-auth --kind=prd --project-root="$DIR" 2>/dev/null; then
  ko "5.1 should reject"
else
  ok "5.1 missing content-file rejected"
fi
if bash "$SCRIPT" ack --feature-id=01-auth --kind=prd --content-file=/nonexistent --project-root="$DIR" 2>/dev/null; then
  ko "5.2 should reject missing file"
else
  ok "5.2 absent content file rejected"
fi
trash "$DIR" 2>/dev/null || true

# 6. fail marks error
echo ""
echo "[6] fail"
DIR=$(setup_dir)
init_repo_with_ref "$DIR"
out=$(bash "$SCRIPT" fail --feature-id=01-auth --kind=prd --note="fetch timeout" --project-root="$DIR")
echo "$out" | grep -q "fetch-fail:01-auth:prd" && ok "6.1 stdout" || ko "6.1 got: $out"
M="${DIR}/.snap/manifests/01-auth.manifest.json"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "error" ] && ok "6.2 error" || ko "6.2"
[ "$(jq -r '.refs.prd.error_note' "$M")" = "fetch timeout" ] && ok "6.3 note" || ko "6.3"
trash "$DIR" 2>/dev/null || true

# 7. check-mark dirty when remote newer
echo ""
echo "[7] check-mark dirty"
DIR=$(setup_dir)
init_repo_with_ref "$DIR"
M="${DIR}/.snap/manifests/01-auth.manifest.json"
LOCAL_TS=$(jq -r '.refs.prd.synced_at' "$M")
REMOTE_NEWER="2099-01-01T00:00:00Z"
out=$(bash "$SCRIPT" check-mark --feature-id=01-auth --kind=prd --remote-edited="$REMOTE_NEWER" --project-root="$DIR")
echo "$out" | grep -q "dirty" && ok "7.1 dirty stdout" || ko "7.1 got: $out"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "dirty" ] && ok "7.2 marked dirty" || ko "7.2"
trash "$DIR" 2>/dev/null || true

# 8. check-mark up-to-date when remote older
echo ""
echo "[8] check-mark up-to-date"
DIR=$(setup_dir)
init_repo_with_ref "$DIR"
M="${DIR}/.snap/manifests/01-auth.manifest.json"
out=$(bash "$SCRIPT" check-mark --feature-id=01-auth --kind=prd --remote-edited="2000-01-01T00:00:00Z" --project-root="$DIR")
echo "$out" | grep -q "up-to-date" && ok "8.1 stdout up-to-date" || ko "8.1 got: $out"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "synced" ] && ok "8.2 stays synced" || ko "8.2"
trash "$DIR" 2>/dev/null || true

# 9. invalid kind
echo ""
echo "[9] invalid kind"
DIR=$(setup_dir)
init_repo_with_ref "$DIR"
if bash "$SCRIPT" plan --feature-id=01-auth --kind=bogus --project-root="$DIR" 2>/dev/null; then
  ko "9.1 should reject"
else
  ok "9.1 bad kind rejected"
fi
trash "$DIR" 2>/dev/null || true

# 10. usage
echo ""
echo "[10] usage"
bash "$SCRIPT" 2>/dev/null; [ $? -eq 1 ] && ok "10.1 no args = 1" || ko "10.1"
bash "$SCRIPT" --help >/dev/null; [ $? -eq 0 ] && ok "10.2 --help = 0" || ko "10.2"

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
