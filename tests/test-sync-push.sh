#!/usr/bin/env bash
# Tests for skills/_shared/sync-push.sh
# Usage: bash tests/test-sync-push.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/sync-push.sh"
SETUP="${ROOT}/skills/_shared/setup-snap-dir.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-push-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# init repo + manifest for feature 01-auth
init_repo() {
  local dir="$1"
  bash "$SETUP" --project-root="$dir" --story-id=01-auth --story-name="Auth" >/dev/null
}

echo "=== sync-push.sh tests ==="

# 1. staging-path returns kind-specific path
echo ""
echo "[1] staging-path"
DIR=$(setup_dir)
init_repo "$DIR"
p=$(bash "$SCRIPT" staging-path --story-id=01-auth --kind=prd --project-root="$DIR")
[ "$p" = "${DIR}/.snap/PRDs/01-auth.md" ] && ok "1.1 prd path" || ko "1.1 got: $p"
p=$(bash "$SCRIPT" staging-path --story-id=01-auth --kind=tickets --project-root="$DIR")
[ "$p" = "${DIR}/.snap/tickets/01-auth.json" ] && ok "1.2 tickets path" || ko "1.2 got: $p"
p=$(bash "$SCRIPT" staging-path --story-id=01-auth --kind=design-gallery --project-root="$DIR")
[ "$p" = "${DIR}/.snap/designs/01-auth" ] && ok "1.3 design-gallery path" || ko "1.3 got: $p"
p=$(bash "$SCRIPT" staging-path --story-id=01-auth --kind=design-gallery --screen=login.png --project-root="$DIR")
[ "$p" = "${DIR}/.snap/designs/01-auth/login.png" ] && ok "1.4 design-gallery with screen" || ko "1.4 got: $p"
trash "$DIR" 2>/dev/null || true

# 2. plan reports exists=false then true
echo ""
echo "[2] plan exists"
DIR=$(setup_dir)
init_repo "$DIR"
out=$(bash "$SCRIPT" plan --story-id=01-auth --kind=prd --project-root="$DIR")
[ "$(echo "$out" | jq -r '.exists')" = "false" ] && ok "2.1 exists=false" || ko "2.1"
[ "$(echo "$out" | jq -r '.kind')" = "prd" ] && ok "2.2 kind in plan" || ko "2.2"
mkdir -p "${DIR}/.snap/PRDs" && echo "x" > "${DIR}/.snap/PRDs/01-auth.md"
out=$(bash "$SCRIPT" plan --story-id=01-auth --kind=prd --project-root="$DIR")
[ "$(echo "$out" | jq -r '.exists')" = "true" ] && ok "2.3 exists=true" || ko "2.3"
trash "$DIR" 2>/dev/null || true

# 3. plan fails if manifest missing
echo ""
echo "[3] plan no manifest"
DIR=$(setup_dir)
if bash "$SCRIPT" plan --story-id=01-auth --kind=prd --project-root="$DIR" 2>/dev/null; then
  ko "3.1 should fail without manifest"
else
  ok "3.1 missing manifest rejected"
fi
trash "$DIR" 2>/dev/null || true

# 4. ack updates manifest, trashes staging
echo ""
echo "[4] ack updates manifest + trashes staging"
DIR=$(setup_dir)
init_repo "$DIR"
mkdir -p "${DIR}/.snap/PRDs" && echo "PRD" > "${DIR}/.snap/PRDs/01-auth.md"
out=$(bash "$SCRIPT" ack --story-id=01-auth --kind=prd --platform=affine --url=https://example.com/p --page-id=page-1 --project-root="$DIR")
echo "$out" | grep -q "ack:01-auth:prd:synced" && ok "4.1 stdout ok" || ko "4.1 got: $out"
M="${DIR}/.snap/manifests/01-auth.manifest.json"
[ "$(jq -r '.refs.prd.platform' "$M")" = "affine" ] && ok "4.2 platform set" || ko "4.2"
[ "$(jq -r '.refs.prd.url' "$M")" = "https://example.com/p" ] && ok "4.3 url set" || ko "4.3"
[ "$(jq -r '.refs.prd.page_id' "$M")" = "page-1" ] && ok "4.4 page_id set" || ko "4.4"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "synced" ] && ok "4.5 sync_status synced" || ko "4.5"
[ ! -f "${DIR}/.snap/PRDs/01-auth.md" ] && ok "4.6 staging trashed" || ko "4.6 still present"
trash "$DIR" 2>/dev/null || true

# 5. ack --no-trash keeps staging
echo ""
echo "[5] ack --no-trash"
DIR=$(setup_dir)
init_repo "$DIR"
mkdir -p "${DIR}/.snap/PRDs" && echo "PRD" > "${DIR}/.snap/PRDs/01-auth.md"
bash "$SCRIPT" ack --story-id=01-auth --kind=prd --platform=affine --url=u --no-trash --project-root="$DIR" >/dev/null
[ -f "${DIR}/.snap/PRDs/01-auth.md" ] && ok "5.1 staging preserved" || ko "5.1"
trash "$DIR" 2>/dev/null || true

# 6. ack missing platform/url rejected
echo ""
echo "[6] ack required args"
DIR=$(setup_dir)
init_repo "$DIR"
if bash "$SCRIPT" ack --story-id=01-auth --kind=prd --url=u --project-root="$DIR" 2>/dev/null; then
  ko "6.1 should reject missing platform"
else
  ok "6.1 missing platform rejected"
fi
if bash "$SCRIPT" ack --story-id=01-auth --kind=prd --platform=affine --project-root="$DIR" 2>/dev/null; then
  ko "6.2 should reject missing url"
else
  ok "6.2 missing url rejected"
fi
trash "$DIR" 2>/dev/null || true

# 7. fail keeps staging, marks error
echo ""
echo "[7] fail"
DIR=$(setup_dir)
init_repo "$DIR"
mkdir -p "${DIR}/.snap/PRDs" && echo "PRD" > "${DIR}/.snap/PRDs/01-auth.md"
out=$(bash "$SCRIPT" fail --story-id=01-auth --kind=prd --note="MCP timeout" --project-root="$DIR")
echo "$out" | grep -q "fail:01-auth:prd:error" && ok "7.1 stdout" || ko "7.1 got: $out"
M="${DIR}/.snap/manifests/01-auth.manifest.json"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "error" ] && ok "7.2 sync_status=error" || ko "7.2"
[ "$(jq -r '.refs.prd.error_note' "$M")" = "MCP timeout" ] && ok "7.3 error_note" || ko "7.3"
[ -f "${DIR}/.snap/PRDs/01-auth.md" ] && ok "7.4 staging preserved on fail" || ko "7.4"
trash "$DIR" 2>/dev/null || true

# 8. mark status
echo ""
echo "[8] mark"
DIR=$(setup_dir)
init_repo "$DIR"
bash "$SCRIPT" mark --story-id=01-auth --kind=prd --status=dirty --project-root="$DIR" >/dev/null
M="${DIR}/.snap/manifests/01-auth.manifest.json"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "dirty" ] && ok "8.1 dirty" || ko "8.1"
if bash "$SCRIPT" mark --story-id=01-auth --kind=prd --status=bogus --project-root="$DIR" 2>/dev/null; then
  ko "8.2 should reject invalid status"
else
  ok "8.2 invalid status rejected"
fi
trash "$DIR" 2>/dev/null || true

# 9. invalid kind rejected
echo ""
echo "[9] invalid kind"
DIR=$(setup_dir)
init_repo "$DIR"
if bash "$SCRIPT" plan --story-id=01-auth --kind=bogus --project-root="$DIR" 2>/dev/null; then
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
bash "$SCRIPT" bogus --story-id=01-auth --kind=prd 2>/dev/null; [ $? -eq 1 ] && ok "10.3 unknown subcmd = 1" || ko "10.3"

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
