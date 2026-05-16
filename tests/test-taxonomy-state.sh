#!/usr/bin/env bash
# Tests for skills/_shared/taxonomy-state.sh
# Usage: bash tests/test-taxonomy-state.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/taxonomy-state.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-tax-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== taxonomy-state.sh tests ==="

# 1. init creates valid file
echo ""
echo "[1] init"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
F="${DIR}/.snap/manifests/_taxonomy.json"
[ -f "$F" ] && ok "1.1 file created" || ko "1.1 missing"
jq empty "$F" 2>/dev/null && ok "1.2 valid JSON" || ko "1.2 invalid JSON"
[ "$(jq -r '.schema_version' "$F")" = "1.1.0" ] && ok "1.3 schema_version" || ko "1.3"
trash "$DIR" 2>/dev/null || true

# 2. add-domain (positional args)
echo ""
echo "[2] add-domain"
DIR=$(setup_dir)
bash "$SCRIPT" add-domain "auth" "Authentication" "page-abc" "https://example.com/auth" --project-root="$DIR"
F="${DIR}/.snap/manifests/_taxonomy.json"
[ "$(jq -r '.domains.auth.page_id' "$F")" = "page-abc" ] && ok "2.1 page_id stored" || ko "2.1"
[ "$(jq -r '.domains.auth.title' "$F")" = "Authentication" ] && ok "2.2 title stored" || ko "2.2"
[ "$(jq -r '.domains.auth.url' "$F")" = "https://example.com/auth" ] && ok "2.3 url stored" || ko "2.3"
trash "$DIR" 2>/dev/null || true

# 3. add-domain bad slug rejected
echo ""
echo "[3] add-domain bad slug"
DIR=$(setup_dir)
if bash "$SCRIPT" add-domain "Bad Slug!" "T" "pid" --project-root="$DIR" 2>/dev/null; then
  ko "3.1 should reject"
else
  ok "3.1 invalid slug rejected"
fi
trash "$DIR" 2>/dev/null || true

# 4. add-domain missing page_id
echo ""
echo "[4] add-domain missing page_id"
DIR=$(setup_dir)
if bash "$SCRIPT" add-domain "auth" "T" "" --project-root="$DIR" 2>/dev/null; then
  ko "4.1 should reject empty pid"
else
  ok "4.1 empty page_id rejected"
fi
trash "$DIR" 2>/dev/null || true

# 5. add-journey requires domain first
echo ""
echo "[5] add-journey requires existing domain"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
if bash "$SCRIPT" add-journey "noexist" "j" "T" "pid" --project-root="$DIR" 2>/dev/null; then
  ko "5.1 should fail when domain missing"
else
  ok "5.1 add-journey rejects missing domain"
fi
trash "$DIR" 2>/dev/null || true

# 6. add-journey happy path
echo ""
echo "[6] add-journey"
DIR=$(setup_dir)
bash "$SCRIPT" add-domain "auth" "Auth" "d-pid" --project-root="$DIR"
bash "$SCRIPT" add-journey "auth" "signup" "Sign up" "j-pid" --project-root="$DIR"
F="${DIR}/.snap/manifests/_taxonomy.json"
[ "$(jq -r '.domains.auth.journeys.signup.page_id' "$F")" = "j-pid" ] && ok "6.1 journey page_id" || ko "6.1"
trash "$DIR" 2>/dev/null || true

# 7. add-top-journey
echo ""
echo "[7] add-top-journey"
DIR=$(setup_dir)
bash "$SCRIPT" add-top-journey "onboarding" "Onboarding" "top-pid" --project-root="$DIR"
F="${DIR}/.snap/manifests/_taxonomy.json"
[ "$(jq -r '.journeys.onboarding.page_id' "$F")" = "top-pid" ] && ok "7.1 top journey stored" || ko "7.1"
trash "$DIR" 2>/dev/null || true

# 8. get-domain / get-journey
echo ""
echo "[8] get-* round-trip"
DIR=$(setup_dir)
bash "$SCRIPT" add-domain "auth" "Auth" "d-pid" --project-root="$DIR"
bash "$SCRIPT" add-journey "auth" "signup" "Sign up" "j-pid" --project-root="$DIR"
d=$(bash "$SCRIPT" get-domain "auth" --project-root="$DIR")
[ -n "$d" ] && [ "$(echo "$d" | jq -r '.page_id')" = "d-pid" ] && ok "8.1 get-domain" || ko "8.1"
j=$(bash "$SCRIPT" get-journey "auth" "signup" --project-root="$DIR")
[ "$(echo "$j" | jq -r '.page_id')" = "j-pid" ] && ok "8.2 get-journey" || ko "8.2"
empty=$(bash "$SCRIPT" get-domain "noexist" --project-root="$DIR")
[ -z "$empty" ] && ok "8.3 get-domain missing → empty" || ko "8.3 got: $empty"
trash "$DIR" 2>/dev/null || true

# 9. has-domain / has-journey
echo ""
echo "[9] has-*"
DIR=$(setup_dir)
bash "$SCRIPT" add-domain "auth" "Auth" "d-pid" --project-root="$DIR"
bash "$SCRIPT" add-journey "auth" "signup" "Sign up" "j-pid" --project-root="$DIR"
bash "$SCRIPT" has-domain "auth" --project-root="$DIR" && ok "9.1 has-domain present" || ko "9.1"
bash "$SCRIPT" has-domain "noexist" --project-root="$DIR" 2>/dev/null && ko "9.2 should be absent" || ok "9.2 has-domain absent"
bash "$SCRIPT" has-journey "auth" "signup" --project-root="$DIR" && ok "9.3 has-journey present" || ko "9.3"
trash "$DIR" 2>/dev/null || true

# 10. list-domains / list-journeys
echo ""
echo "[10] list-*"
DIR=$(setup_dir)
bash "$SCRIPT" add-domain "auth" "Auth" "d-pid" --project-root="$DIR"
bash "$SCRIPT" add-domain "billing" "Billing" "b-pid" --project-root="$DIR"
bash "$SCRIPT" add-journey "auth" "signup" "Sign up" "j-pid" --project-root="$DIR"
bash "$SCRIPT" add-top-journey "onboarding" "Ob" "ob-pid" --project-root="$DIR"
domains=$(bash "$SCRIPT" list-domains --project-root="$DIR" | sort | paste -sd, -)
[ "$domains" = "auth,billing" ] && ok "10.1 list-domains" || ko "10.1 got: $domains"
journeys=$(bash "$SCRIPT" list-journeys --project-root="$DIR" | sort | paste -sd, -)
[ "$journeys" = "_/onboarding,auth/signup" ] && ok "10.2 list-journeys (all)" || ko "10.2 got: $journeys"
trash "$DIR" 2>/dev/null || true

# 11. set-workspace
echo ""
echo "[11] set-workspace"
DIR=$(setup_dir)
bash "$SCRIPT" set-workspace --platform=affine --workspace-id=ws-1 --root-page-id=root-1 --root-url=https://example.com/r --project-root="$DIR"
F="${DIR}/.snap/manifests/_taxonomy.json"
[ "$(jq -r '.workspace.platform' "$F")" = "affine" ] && ok "11.1 platform" || ko "11.1"
[ "$(jq -r '.workspace.workspace_id' "$F")" = "ws-1" ] && ok "11.2 workspace_id" || ko "11.2"
[ "$(jq -r '.workspace.root_page_id' "$F")" = "root-1" ] && ok "11.3 root_page_id" || ko "11.3"
ws=$(bash "$SCRIPT" get-workspace --project-root="$DIR")
[ "$(echo "$ws" | jq -r '.platform')" = "affine" ] && ok "11.4 get-workspace" || ko "11.4"
trash "$DIR" 2>/dev/null || true

# 12. validate empty + happy
echo ""
echo "[12] validate"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" validate --project-root="$DIR" 2>/dev/null && ok "12.1 empty valid" || ko "12.1"
bash "$SCRIPT" add-domain "auth" "Auth" "d-pid" --project-root="$DIR"
bash "$SCRIPT" add-journey "auth" "signup" "Sign up" "j-pid" --project-root="$DIR"
bash "$SCRIPT" validate --project-root="$DIR" 2>/dev/null && ok "12.2 happy valid" || ko "12.2"
trash "$DIR" 2>/dev/null || true

# 13. validate detects missing page_id
echo ""
echo "[13] validate detects errors"
DIR=$(setup_dir)
mkdir -p "$DIR/.snap/manifests"
cat > "$DIR/.snap/manifests/_taxonomy.json" <<'EOF'
{ "schema_version": "1.0.0", "domains": { "auth": { "title": "Auth" } } }
EOF
if bash "$SCRIPT" validate --project-root="$DIR" 2>/dev/null; then
  ko "13.1 should fail (missing page_id)"
else
  ok "13.1 missing page_id rejected"
fi
trash "$DIR" 2>/dev/null || true

# 14. path
echo ""
echo "[14] path"
DIR=$(setup_dir)
p=$(bash "$SCRIPT" path --project-root="$DIR")
[ "$p" = "${DIR}/.snap/manifests/_taxonomy.json" ] && ok "14.1 path printed" || ko "14.1 got: $p"
trash "$DIR" 2>/dev/null || true

# 15. idempotency: re-adding same domain merges
echo ""
echo "[15] idempotent add-domain"
DIR=$(setup_dir)
bash "$SCRIPT" add-domain "auth" "Auth" "pid-1" --project-root="$DIR"
bash "$SCRIPT" add-journey "auth" "signup" "Sign up" "j-pid" --project-root="$DIR"
bash "$SCRIPT" add-domain "auth" "Auth Renamed" "pid-2" --project-root="$DIR"
F="${DIR}/.snap/manifests/_taxonomy.json"
[ "$(jq -r '.domains.auth.title' "$F")" = "Auth Renamed" ] && ok "15.1 title updated" || ko "15.1"
[ "$(jq -r '.domains.auth.page_id' "$F")" = "pid-2" ] && ok "15.2 page_id updated" || ko "15.2"
[ "$(jq -r '.domains.auth.journeys.signup.page_id' "$F")" = "j-pid" ] && ok "15.3 journeys preserved" || ko "15.3"
trash "$DIR" 2>/dev/null || true

# 16. usage / help
echo ""
echo "[16] usage"
bash "$SCRIPT" 2>/dev/null; [ $? -eq 2 ] && ok "16.1 no subcmd = exit 2" || ko "16.1"
bash "$SCRIPT" --help >/dev/null; [ $? -eq 0 ] && ok "16.2 --help = exit 0" || ko "16.2"
bash "$SCRIPT" bogus-cmd 2>/dev/null; [ $? -eq 2 ] && ok "16.3 unknown = exit 2" || ko "16.3"

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
