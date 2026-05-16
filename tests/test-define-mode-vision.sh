#!/usr/bin/env bash
# /define --mode=vision — end-to-end shape of step-00-vision-edit operations
# against taxonomy-state.sh. No LLM, no AskUserQuestion — verifies the
# helpers the step relies on produce a valid _taxonomy.json.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAX="${ROOT}/skills/_shared/taxonomy-state.sh"
SCHEMA="${ROOT}/skills/_shared/schemas/taxonomy.schema.json"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-vision-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== /define --mode=vision ==="

# 1. init creates a valid taxonomy file with empty workspace
DIR=$(setup_dir)
bash "$TAX" init --project-root="$DIR" >/dev/null
F="${DIR}/.snap/manifests/_taxonomy.json"
[ -f "$F" ] && ok "1.1 _taxonomy.json created" || ko "1.1" "missing"
[ "$(jq -r '.schema_version' "$F")" = "1.1.0" ] && ok "1.2 schema_version 1.1.0" || ko "1.2" "wrong"

# 2. set-vision persists workspace.vision
VISION="A platform that helps freelance designers organize and ship client work end-to-end."
bash "$TAX" set-vision "$VISION" --project-root="$DIR" >/dev/null
got=$(jq -r '.workspace.vision' "$F")
[ "$got" = "$VISION" ] && ok "2.1 vision round-trip" || ko "2.1" "diff"

# 3. set-principles persists array (unique, ≥5 chars)
PRINCIPLES='["Ship daily","Designer first","Compose not bundle"]'
bash "$TAX" set-principles "$PRINCIPLES" --project-root="$DIR" >/dev/null
n=$(jq '.workspace.principles | length' "$F")
[ "$n" = "3" ] && ok "3.1 principles count" || ko "3.1" "n=$n"
[ "$(jq -r '.workspace.principles[0]' "$F")" = "Ship daily" ] \
  && ok "3.2 principle order preserved" || ko "3.2" "reordered"

# 4. set-north-star with metric+current+target+horizon
bash "$TAX" set-north-star "WAU" "1200" "5000" "Q3 2026" --project-root="$DIR" >/dev/null
[ "$(jq -r '.workspace.north_star.metric'  "$F")" = "WAU"     ] && ok "4.1 metric"  || ko "4.1" "diff"
[ "$(jq -r '.workspace.north_star.current' "$F")" = "1200"    ] && ok "4.2 current" || ko "4.2" "diff"
[ "$(jq -r '.workspace.north_star.target'  "$F")" = "5000"    ] && ok "4.3 target"  || ko "4.3" "diff"
[ "$(jq -r '.workspace.north_star.horizon' "$F")" = "Q3 2026" ] && ok "4.4 horizon" || ko "4.4" "diff"

# 5. set-north-star with metric only (current/target/horizon optional)
DIR2=$(setup_dir)
bash "$TAX" init --project-root="$DIR2" >/dev/null
bash "$TAX" set-north-star "Activation" --project-root="$DIR2" >/dev/null
F2="${DIR2}/.snap/manifests/_taxonomy.json"
[ "$(jq -r '.workspace.north_star.metric' "$F2")" = "Activation" ] \
  && ok "5.1 north-star metric-only" || ko "5.1" "diff"

# 6. final taxonomy validates against schema (ajv draft 2020)
if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "$F" --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "6.1 ajv validates full workspace"
  else
    ko "6.1" "ajv rejected"
  fi
else
  ok "6.1 ajv not installed, skipping (CI runs validate-schemas.sh)"
fi

# 7. workspace + journeys can coexist (vision mode does not wipe domains)
bash "$TAX" add-domain "auth" "Authentication" "page-auth-123" --project-root="$DIR" >/dev/null
nd=$(jq '.domains | length' "$F")
[ "$nd" = "1" ] && ok "7.1 vision edit preserves domains" || ko "7.1" "n=$nd"
[ "$(jq -r '.workspace.vision' "$F")" = "$VISION" ] \
  && ok "7.2 vision untouched after domain add" || ko "7.2" "lost"

trash "$DIR" "$DIR2" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
