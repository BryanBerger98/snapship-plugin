#!/usr/bin/env bash
# Tests for skills/_shared/setup-product-dir.sh
# Usage: bash tests/test-setup-product-dir.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/setup-product-dir.sh"
SCHEMA="${ROOT}/skills/_shared/schemas/meta.schema.json"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-setupdir-XXXXXX; }

ok() {
  echo "  PASS  $1"
  PASS=$((PASS + 1))
}
ko() {
  echo "  FAIL  $1"
  FAIL=$((FAIL + 1))
  ERRORS+=("$1")
}

if command -v ajv >/dev/null 2>&1; then
  AJV="ajv"
elif command -v npx >/dev/null 2>&1; then
  AJV="npx -y ajv-cli"
else
  AJV=""
fi

echo "=== setup-product-dir.sh tests ==="

# 1. Root init
echo ""
echo "[1] Root init (no feature)"
DIR=$(setup_dir)
out=$(bash "$SCRIPT" --project-root="$DIR")
[ "$out" = "${DIR}/.claude/product" ] && ok "1.1 stdout = product dir path" || ko "1.1 stdout '$out' != '${DIR}/.claude/product'"
[ -d "${DIR}/.claude/product/features" ] && ok "1.2 features/ created" || ko "1.2 features/ missing"
[ -f "${DIR}/.claude/product/index.md" ] && ok "1.3 index.md created" || ko "1.3 index.md missing"
grep -q "Product Index" "${DIR}/.claude/product/index.md" && ok "1.4 index.md has header" || ko "1.4 index.md header missing"
trash "$DIR" 2>/dev/null || true

# 2. Idempotency: 2nd run preserves index.md content
echo ""
echo "[2] Idempotency"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" >/dev/null
echo "custom content" >> "${DIR}/.claude/product/index.md"
bash "$SCRIPT" --project-root="$DIR" >/dev/null
grep -q "custom content" "${DIR}/.claude/product/index.md" && ok "2.1 index.md preserved on re-run" || ko "2.1 index.md overwritten"
trash "$DIR" 2>/dev/null || true

# 3. Feature scaffold
echo ""
echo "[3] Feature scaffold"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" --lang=fr --green-field=true >/dev/null
FEATDIR="${DIR}/.claude/product/features/01-auth"
[ -d "${FEATDIR}/wireframes" ] && ok "3.1 wireframes/ created" || ko "3.1 wireframes/ missing"
[ -f "${FEATDIR}/meta.json" ] && ok "3.2 meta.json created" || ko "3.2 meta.json missing"
[ -f "${FEATDIR}/progress.md" ] && ok "3.3 progress.md created" || ko "3.3 progress.md missing"

if [ -f "${FEATDIR}/meta.json" ]; then
  fid=$(jq -r '.feature_id' "${FEATDIR}/meta.json")
  fname=$(jq -r '.feature_name' "${FEATDIR}/meta.json")
  state=$(jq -r '.state' "${FEATDIR}/meta.json")
  lang=$(jq -r '.lang' "${FEATDIR}/meta.json")
  gf=$(jq -r '.green_field' "${FEATDIR}/meta.json")
  [ "$fid" = "01-auth" ] && ok "3.4 meta.feature_id" || ko "3.4 meta.feature_id = $fid"
  [ "$fname" = "Auth" ] && ok "3.5 meta.feature_name" || ko "3.5 meta.feature_name = $fname"
  [ "$state" = "defined" ] && ok "3.6 meta.state = defined" || ko "3.6 meta.state = $state"
  [ "$lang" = "fr" ] && ok "3.7 meta.lang = fr" || ko "3.7 meta.lang = $lang"
  [ "$gf" = "true" ] && ok "3.8 meta.green_field = true" || ko "3.8 meta.green_field = $gf"

  # Schema validation
  if [ -n "$AJV" ]; then
    if $AJV validate --spec=draft2020 -s "$SCHEMA" -d "${FEATDIR}/meta.json" --strict=false >/dev/null 2>&1; then
      ok "3.9 meta.json validates vs schema"
    else
      ko "3.9 meta.json fails schema validation"
    fi
  fi
fi
trash "$DIR" 2>/dev/null || true

# 4. Feature idempotency
echo ""
echo "[4] Feature idempotency"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" >/dev/null
echo "custom progress" >> "${DIR}/.claude/product/features/01-auth/progress.md"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth Renamed" >/dev/null
grep -q "custom progress" "${DIR}/.claude/product/features/01-auth/progress.md" && ok "4.1 progress.md preserved" || ko "4.1 progress.md overwritten"
fname=$(jq -r '.feature_name' "${DIR}/.claude/product/features/01-auth/meta.json")
[ "$fname" = "Auth" ] && ok "4.2 meta.json preserved (no overwrite)" || ko "4.2 meta.feature_name overwritten to '$fname'"
trash "$DIR" 2>/dev/null || true

# 5. Invalid feature_id format
echo ""
echo "[5] Invalid feature_id format"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=auth --feature-name="X" >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.1 'auth' rejected (not NN-kebab)" || ko "5.1 'auth' accepted"
bash "$SCRIPT" --project-root="$DIR" --feature-id=1-auth --feature-name="X" >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.2 '1-auth' rejected (single digit)" || ko "5.2 '1-auth' accepted"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-Auth --feature-name="X" >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.3 '01-Auth' rejected (uppercase)" || ko "5.3 '01-Auth' accepted"
trash "$DIR" 2>/dev/null || true

# 6. Missing feature-name with feature-id
echo ""
echo "[6] Missing --feature-name with --feature-id"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth >/dev/null 2>&1
[ $? -ne 0 ] && ok "6.1 fail without --feature-name" || ko "6.1 succeeded without --feature-name"
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
