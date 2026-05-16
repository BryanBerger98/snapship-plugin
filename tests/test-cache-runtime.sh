#!/usr/bin/env bash
# Tests for skills/_shared/cache-runtime.sh
# Usage: bash tests/test-cache-runtime.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/cache-runtime.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-cache-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== cache-runtime.sh tests ==="

# 1. id-gen produces unique IDs with prefix
echo ""
echo "[1] id-gen"
ID1=$(bash "$SCRIPT" id-gen --prefix=ticket)
ID2=$(bash "$SCRIPT" id-gen --prefix=ticket)
echo "$ID1" | grep -qE '^ticket-[0-9]{8}T[0-9]{6}-[a-f0-9]{6}$' && ok "1.1 format prefix-ts-rand" || ko "1.1 got: $ID1"
[ "$ID1" != "$ID2" ] && ok "1.2 unique across calls" || ko "1.2 duplicate: $ID1"
ID_NO_PREFIX=$(bash "$SCRIPT" id-gen)
echo "$ID_NO_PREFIX" | grep -qE '^[0-9]{8}T[0-9]{6}-[a-f0-9]{6}$' && ok "1.3 no prefix → ts-rand" || ko "1.3 got: $ID_NO_PREFIX"

# 2. init creates directory
echo ""
echo "[2] init"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=test)
bash "$SCRIPT" init "$SID" --project-root="$DIR"
[ -d "${DIR}/.snap/.runtime/${SID}" ] && ok "2.1 dir created" || ko "2.1 missing"
# Idempotent : second init OK
bash "$SCRIPT" init "$SID" --project-root="$DIR" && ok "2.2 idempotent" || ko "2.2"
trash "$DIR" 2>/dev/null || true

# 3. write + read roundtrip
echo ""
echo "[3] write + read"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=test)
bash "$SCRIPT" init "$SID" --project-root="$DIR"
echo '{"draft":"hello"}' | bash "$SCRIPT" write "$SID" tickets.json --project-root="$DIR"
out=$(bash "$SCRIPT" read "$SID" tickets.json --project-root="$DIR")
[ "$out" = '{"draft":"hello"}' ] && ok "3.1 roundtrip preserves content" || ko "3.1 got: $out"
trash "$DIR" 2>/dev/null || true

# 4. write rejects path traversal
echo ""
echo "[4] write rejects bad filenames"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=test)
bash "$SCRIPT" init "$SID" --project-root="$DIR"
echo '{}' | bash "$SCRIPT" write "$SID" "../escape" --project-root="$DIR" 2>/dev/null && ko "4.1 should reject ../" || ok "4.1 rejects ../"
echo '{}' | bash "$SCRIPT" write "$SID" "sub/file" --project-root="$DIR" 2>/dev/null && ko "4.2 should reject sub/" || ok "4.2 rejects sub/"
echo '{}' | bash "$SCRIPT" write "$SID" "/abs" --project-root="$DIR" 2>/dev/null && ko "4.3 should reject /abs" || ok "4.3 rejects absolute path"
trash "$DIR" 2>/dev/null || true

# 5. write requires init
echo ""
echo "[5] write without init fails"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=test)
echo '{}' | bash "$SCRIPT" write "$SID" t.json --project-root="$DIR" 2>/dev/null && ko "5.1 should fail" || ok "5.1 write fails before init"
trash "$DIR" 2>/dev/null || true

# 6. read missing file
echo ""
echo "[6] read missing"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=test)
bash "$SCRIPT" init "$SID" --project-root="$DIR"
bash "$SCRIPT" read "$SID" absent.json --project-root="$DIR" 2>/dev/null && ko "6.1 should fail" || ok "6.1 read absent → exit 1"
trash "$DIR" 2>/dev/null || true

# 7. exists subject / exists file
echo ""
echo "[7] exists"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=test)
bash "$SCRIPT" exists "$SID" --project-root="$DIR" 2>/dev/null && ko "7.1 absent subject should be 1" || ok "7.1 absent subject exit 1"
bash "$SCRIPT" init "$SID" --project-root="$DIR"
bash "$SCRIPT" exists "$SID" --project-root="$DIR" && ok "7.2 present subject exit 0" || ko "7.2"
bash "$SCRIPT" exists "$SID" foo.json --project-root="$DIR" 2>/dev/null && ko "7.3 absent file should be 1" || ok "7.3 absent file exit 1"
echo '{}' | bash "$SCRIPT" write "$SID" foo.json --project-root="$DIR"
bash "$SCRIPT" exists "$SID" foo.json --project-root="$DIR" && ok "7.4 present file exit 0" || ko "7.4"
trash "$DIR" 2>/dev/null || true

# 8. purge removes directory (idempotent)
echo ""
echo "[8] purge"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=test)
bash "$SCRIPT" init "$SID" --project-root="$DIR"
echo '{}' | bash "$SCRIPT" write "$SID" t.json --project-root="$DIR"
bash "$SCRIPT" purge "$SID" --project-root="$DIR"
[ ! -d "${DIR}/.snap/.runtime/${SID}" ] && ok "8.1 dir gone" || ko "8.1 still present"
bash "$SCRIPT" purge "$SID" --project-root="$DIR" && ok "8.2 idempotent purge" || ko "8.2"
trash "$DIR" 2>/dev/null || true

# 9. isolation across two concurrent subjects
echo ""
echo "[9] isolation"
DIR=$(setup_dir)
SID_A=$(bash "$SCRIPT" id-gen --prefix=run-a)
SID_B=$(bash "$SCRIPT" id-gen --prefix=run-b)
bash "$SCRIPT" init "$SID_A" --project-root="$DIR"
bash "$SCRIPT" init "$SID_B" --project-root="$DIR"
echo '{"who":"a"}' | bash "$SCRIPT" write "$SID_A" state.json --project-root="$DIR"
echo '{"who":"b"}' | bash "$SCRIPT" write "$SID_B" state.json --project-root="$DIR"
a=$(bash "$SCRIPT" read "$SID_A" state.json --project-root="$DIR")
b=$(bash "$SCRIPT" read "$SID_B" state.json --project-root="$DIR")
[ "$a" = '{"who":"a"}' ] && ok "9.1 A unaffected by B" || ko "9.1 got: $a"
[ "$b" = '{"who":"b"}' ] && ok "9.2 B unaffected by A" || ko "9.2 got: $b"
bash "$SCRIPT" purge "$SID_A" --project-root="$DIR"
bash "$SCRIPT" exists "$SID_A" --project-root="$DIR" 2>/dev/null && ko "9.3 A still here" || ok "9.3 A purged"
bash "$SCRIPT" exists "$SID_B" --project-root="$DIR" && ok "9.4 B still alive" || ko "9.4 B accidentally purged"
trash "$DIR" 2>/dev/null || true

# 10. trap auto-purge pattern
echo ""
echo "[10] trap EXIT auto-purge"
DIR=$(setup_dir)
SID=$(bash "$SCRIPT" id-gen --prefix=trap)
bash "$SCRIPT" init "$SID" --project-root="$DIR"
( trap 'bash "'"$SCRIPT"'" purge "'"$SID"'" --project-root="'"$DIR"'"' EXIT
  echo '{}' | bash "$SCRIPT" write "$SID" t.json --project-root="$DIR"
  true
)
[ ! -d "${DIR}/.snap/.runtime/${SID}" ] && ok "10.1 trap purged subject on normal exit" || ko "10.1 subject still present"

DIR2=$(setup_dir)
SID2=$(bash "$SCRIPT" id-gen --prefix=trap)
bash "$SCRIPT" init "$SID2" --project-root="$DIR2"
( trap 'bash "'"$SCRIPT"'" purge "'"$SID2"'" --project-root="'"$DIR2"'"' EXIT
  echo '{}' | bash "$SCRIPT" write "$SID2" t.json --project-root="$DIR2"
  exit 17
) 2>/dev/null
[ ! -d "${DIR2}/.snap/.runtime/${SID2}" ] && ok "10.2 trap purged on non-zero exit" || ko "10.2 subject still present"
trash "$DIR" "$DIR2" 2>/dev/null || true

# 11. subject-id validation
echo ""
echo "[11] subject-id validation"
DIR=$(setup_dir)
bash "$SCRIPT" init "../bad" --project-root="$DIR" 2>/dev/null && ko "11.1 should reject ../" || ok "11.1 rejects ../"
bash "$SCRIPT" init "a/b" --project-root="$DIR" 2>/dev/null && ko "11.2 should reject /" || ok "11.2 rejects /"
bash "$SCRIPT" init "-leading-dash" --project-root="$DIR" 2>/dev/null && ko "11.3 should reject leading dash" || ok "11.3 rejects leading dash"
bash "$SCRIPT" init "ok-123_v2.beta" --project-root="$DIR" && ok "11.4 accepts kebab/dot/underscore" || ko "11.4"
trash "$DIR" 2>/dev/null || true

# 12. usage / help
echo ""
echo "[12] usage"
bash "$SCRIPT" 2>/dev/null; [ $? -eq 1 ] && ok "12.1 no args = exit 1" || ko "12.1"
bash "$SCRIPT" --help >/dev/null && ok "12.2 --help = 0" || ko "12.2"
bash "$SCRIPT" bogus 2>/dev/null; [ $? -eq 1 ] && ok "12.3 unknown subcmd = 1" || ko "12.3"

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
