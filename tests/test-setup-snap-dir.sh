#!/usr/bin/env bash
# Tests for skills/_shared/setup-snap-dir.sh
# Usage: bash tests/test-setup-snap-dir.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/setup-snap-dir.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-init-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== setup-snap-dir.sh tests ==="

# 1. root scaffold
echo ""
echo "[1] root scaffold"
DIR=$(setup_dir)
out=$(bash "$SCRIPT" --project-root="$DIR")
[ "$out" = "${DIR}/.snap" ] && ok "1.1 prints snap dir" || ko "1.1 got: $out"
for sub in manifests PRDs designs wireframes tickets queues .doc-import; do
  [ -d "${DIR}/.snap/${sub}" ] && ok "1.2 ${sub}/" || ko "1.2 ${sub}/ missing"
done
[ -f "${DIR}/.snap/manifests/_taxonomy.json" ] && ok "1.3 _taxonomy.json" || ko "1.3"
[ -f "${DIR}/.snap/progress.json" ] && ok "1.4 progress.json" || ko "1.4"
[ "$(jq -r '.schema_version' "${DIR}/.snap/manifests/_taxonomy.json")" = "1.0.0" ] && ok "1.5 taxonomy schema_version" || ko "1.5"
[ "$(jq -r '.schema_version' "${DIR}/.snap/progress.json")" = "1.0.0" ] && ok "1.6 progress schema_version" || ko "1.6"
trash "$DIR" 2>/dev/null || true

# 2. idempotent
echo ""
echo "[2] idempotent"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" >/dev/null
# Stamp taxonomy with a domain
jq '.domains.auth = {page_id: "p-1", title: "A", journeys: {}}' "${DIR}/.snap/manifests/_taxonomy.json" > /tmp/t.json && mv /tmp/t.json "${DIR}/.snap/manifests/_taxonomy.json"
bash "$SCRIPT" --project-root="$DIR" >/dev/null
[ "$(jq -r '.domains.auth.page_id' "${DIR}/.snap/manifests/_taxonomy.json")" = "p-1" ] && ok "2.1 existing taxonomy untouched" || ko "2.1"
trash "$DIR" 2>/dev/null || true

# 3. feature manifest creation
echo ""
echo "[3] feature manifest"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Authentication" --lang=fr --green-field=true >/dev/null
M="${DIR}/.snap/manifests/01-auth.manifest.json"
[ -f "$M" ] && ok "3.1 manifest created" || ko "3.1"
[ "$(jq -r '.feature_id' "$M")" = "01-auth" ] && ok "3.2 feature_id" || ko "3.2"
[ "$(jq -r '.feature_name' "$M")" = "Authentication" ] && ok "3.3 feature_name" || ko "3.3"
[ "$(jq -r '.state' "$M")" = "defined" ] && ok "3.4 initial state" || ko "3.4"
[ "$(jq -r '.lang' "$M")" = "fr" ] && ok "3.5 lang" || ko "3.5"
[ "$(jq -r '.green_field' "$M")" = "true" ] && ok "3.6 green_field" || ko "3.6"
[ "$(jq -r '.schema_version' "$M")" = "1.0.0" ] && ok "3.7 schema_version" || ko "3.7"
trash "$DIR" 2>/dev/null || true

# 4. feature manifest idempotent (no overwrite)
echo ""
echo "[4] feature manifest idempotent"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Authentication" >/dev/null
M="${DIR}/.snap/manifests/01-auth.manifest.json"
# Stamp a custom value
jq '.state = "developed"' "$M" > /tmp/t.json && mv /tmp/t.json "$M"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Renamed" >/dev/null
[ "$(jq -r '.state' "$M")" = "developed" ] && ok "4.1 state preserved" || ko "4.1"
[ "$(jq -r '.feature_name' "$M")" = "Authentication" ] && ok "4.2 name preserved (not overwritten)" || ko "4.2"
trash "$DIR" 2>/dev/null || true

# 5. bad feature-id rejected
echo ""
echo "[5] bad feature-id"
DIR=$(setup_dir)
if bash "$SCRIPT" --project-root="$DIR" --feature-id=BAD --feature-name=X 2>/dev/null; then
  ko "5.1 should reject"
else
  ok "5.1 bad feature-id rejected"
fi
trash "$DIR" 2>/dev/null || true

# 6. --feature-id requires --feature-name
echo ""
echo "[6] feature-id without name"
DIR=$(setup_dir)
if bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth 2>/dev/null; then
  ko "6.1 should reject"
else
  ok "6.1 missing feature-name rejected"
fi
trash "$DIR" 2>/dev/null || true

# 7. unknown arg rejected
echo ""
echo "[7] unknown arg"
DIR=$(setup_dir)
if bash "$SCRIPT" --project-root="$DIR" --bogus 2>/dev/null; then
  ko "7.1 should reject"
else
  ok "7.1 unknown arg rejected"
fi
trash "$DIR" 2>/dev/null || true

# 8. --help
echo ""
echo "[8] help"
bash "$SCRIPT" --help >/dev/null; [ $? -eq 0 ] && ok "8.1 --help = 0" || ko "8.1"

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
