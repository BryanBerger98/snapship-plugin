#!/usr/bin/env bash
# Tests scripts/migrate-config-v04-to-v05.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MIGRATE="${REPO_ROOT}/scripts/migrate-config-v04-to-v05.sh"
SCHEMA="${REPO_ROOT}/skills/_shared/schemas/config.schema.json"

PASS=0
FAIL=0
fail() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
pass() { echo "  PASS  $*"; PASS=$((PASS+1)); }

[ -x "$MIGRATE" ] || { echo "ERROR: migrate script not executable: $MIGRATE" >&2; exit 1; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ---------- [1] frame0_api_port migration ----------
echo "[1] frame0_api_port → wireframes.frame0.api_port"
cat > "$TMPDIR/c1.json" <<'JSON'
{
  "version": "1.0",
  "wireframes": { "platform": "frame0", "frame0_api_port": 59999 }
}
JSON
OUT=$("$MIGRATE" --file="$TMPDIR/c1.json" --dry-run 2>/dev/null)
PORT=$(echo "$OUT" | jq -r '.wireframes.frame0.api_port')
HAS_OLD=$(echo "$OUT" | jq 'has("wireframes") and (.wireframes | has("frame0_api_port"))')
[ "$PORT" = "59999" ] && pass "1.1 port preserved nested" || fail "1.1 port not migrated: $PORT"
[ "$HAS_OLD" = "false" ] && pass "1.2 flat key removed" || fail "1.2 flat key still present"

# ---------- [2] penpot_* migrations ----------
echo "[2] penpot_export_dir/file_id/file_name → wireframes.penpot.{...}"
cat > "$TMPDIR/c2.json" <<'JSON'
{
  "version": "1.0",
  "wireframes": {
    "platform": "penpot",
    "penpot_export_dir": "/tmp/wf",
    "penpot_file_id": "abc-123",
    "penpot_file_name": "Project Wireframes"
  }
}
JSON
OUT=$("$MIGRATE" --file="$TMPDIR/c2.json" --dry-run 2>/dev/null)
DIR=$(echo "$OUT" | jq -r '.wireframes.penpot.export_dir')
FID=$(echo "$OUT" | jq -r '.wireframes.penpot.file_id')
FNAME=$(echo "$OUT" | jq -r '.wireframes.penpot.file_name')
HAS_FLAT=$(echo "$OUT" | jq '.wireframes | has("penpot_export_dir") or has("penpot_file_id") or has("penpot_file_name")')
[ "$DIR" = "/tmp/wf" ] && pass "2.1 export_dir migrated" || fail "2.1 export_dir: $DIR"
[ "$FID" = "abc-123" ] && pass "2.2 file_id migrated" || fail "2.2 file_id: $FID"
[ "$FNAME" = "Project Wireframes" ] && pass "2.3 file_name migrated" || fail "2.3 file_name: $FNAME"
[ "$HAS_FLAT" = "false" ] && pass "2.4 flat keys removed" || fail "2.4 flat keys remain"

# ---------- [3] mixed flat + already-nested kept ----------
echo "[3] preserve existing nested blocks"
cat > "$TMPDIR/c3.json" <<'JSON'
{
  "version": "1.0",
  "wireframes": {
    "platform": "frame0",
    "frame0_api_port": 60000,
    "frame0": { "export_source_dir": "/srv/frame0" }
  }
}
JSON
OUT=$("$MIGRATE" --file="$TMPDIR/c3.json" --dry-run 2>/dev/null)
PORT=$(echo "$OUT" | jq -r '.wireframes.frame0.api_port')
ESD=$(echo "$OUT" | jq -r '.wireframes.frame0.export_source_dir')
[ "$PORT" = "60000" ] && pass "3.1 port migrated" || fail "3.1 port: $PORT"
[ "$ESD" = "/srv/frame0" ] && pass "3.2 existing nested preserved" || fail "3.2 export_source_dir: $ESD"

# ---------- [4] idempotent — already v0.5 → exit 2 ----------
echo "[4] idempotent v0.5 → exit 2"
cat > "$TMPDIR/c4.json" <<'JSON'
{
  "version": "1.0",
  "wireframes": { "platform": "frame0", "frame0": { "api_port": 58320 } }
}
JSON
"$MIGRATE" --file="$TMPDIR/c4.json" --dry-run 2>/dev/null
[ "$?" -eq 2 ] && pass "4.1 exit 2 on already-migrated" || fail "4.1 unexpected exit $?"

# ---------- [5] no wireframes block ----------
echo "[5] no wireframes block → exit 2"
cat > "$TMPDIR/c5.json" <<'JSON'
{ "version": "1.0", "repository": { "platform": "github" } }
JSON
"$MIGRATE" --file="$TMPDIR/c5.json" --dry-run 2>/dev/null
[ "$?" -eq 2 ] && pass "5.1 exit 2 when nothing to migrate" || fail "5.1 unexpected exit $?"

# ---------- [6] real write + backup ----------
echo "[6] write mode creates backup"
cat > "$TMPDIR/c6.json" <<'JSON'
{ "version": "1.0", "wireframes": { "platform": "frame0", "frame0_api_port": 12345 } }
JSON
"$MIGRATE" --file="$TMPDIR/c6.json" 2>/dev/null
[ -f "$TMPDIR/c6.json.bak" ] && pass "6.1 backup created" || fail "6.1 no backup"
PORT_AFTER=$(jq -r '.wireframes.frame0.api_port' < "$TMPDIR/c6.json")
HAS_OLD_AFTER=$(jq '.wireframes | has("frame0_api_port")' < "$TMPDIR/c6.json")
[ "$PORT_AFTER" = "12345" ] && pass "6.2 file rewritten nested" || fail "6.2 port not in nested"
[ "$HAS_OLD_AFTER" = "false" ] && pass "6.3 flat key removed in file" || fail "6.3 flat key remains in file"
ORIG_PORT=$(jq -r '.wireframes.frame0_api_port' < "$TMPDIR/c6.json.bak")
[ "$ORIG_PORT" = "12345" ] && pass "6.4 backup preserves original flat key" || fail "6.4 backup wrong: $ORIG_PORT"

# ---------- [7] missing file → exit 1 ----------
echo "[7] missing file → exit 1"
"$MIGRATE" --file="$TMPDIR/nope.json" --dry-run 2>/dev/null
[ "$?" -eq 1 ] && pass "7.1 exit 1 on missing file" || fail "7.1 unexpected exit $?"

# ---------- [8] invalid JSON → exit 1 ----------
echo "[8] invalid JSON → exit 1"
echo "not json" > "$TMPDIR/c8.json"
"$MIGRATE" --file="$TMPDIR/c8.json" --dry-run 2>/dev/null
[ "$?" -eq 1 ] && pass "8.1 exit 1 on invalid JSON" || fail "8.1 unexpected exit $?"

# ---------- [9] migrated output validates against v0.5 schema ----------
echo "[9] migrated output passes v0.5 schema"
if command -v ajv >/dev/null 2>&1; then
  AJV="ajv"
elif command -v npx >/dev/null 2>&1; then
  AJV="npx -y ajv-cli"
else
  AJV=""
fi
if [ -n "$AJV" ]; then
  cat > "$TMPDIR/c9.json" <<'JSON'
{
  "version": "1.0",
  "wireframes": {
    "platform": "penpot",
    "penpot_export_dir": "/tmp/wf",
    "penpot_file_id": "abc-123"
  }
}
JSON
  "$MIGRATE" --file="$TMPDIR/c9.json" 2>/dev/null
  if $AJV validate --spec=draft2020 -s "$SCHEMA" -d "$TMPDIR/c9.json" --strict=false >/dev/null 2>&1; then
    pass "9.1 migrated file validates against schema"
  else
    fail "9.1 migrated file fails schema validation"
  fi
else
  echo "  SKIP  9.1 ajv not available"
fi

echo ""
echo "=== Summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
