#!/usr/bin/env bash
# /define --mode=vision — end-to-end shape of step-00-vision-edit operations
# against taxonomy-state.sh. No LLM, no AskUserQuestion — verifies the
# helpers the step relies on produce a valid _taxonomy.json.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAX="${ROOT}/skills/_shared/taxonomy-state.sh"
DEFST="${ROOT}/skills/_shared/define-state.sh"
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

# 8. Source-of-truth handoff: step-01-vision skip path (N2 fix).
#    A pre-existing _taxonomy.workspace.vision + north_star must mirror into
#    .define-state.json without re-asking. Simulates: --mode=vision first,
#    then --mode=story re-uses the persisted values.
echo ""
echo "[8] source-of-truth handoff to define-state"
DIR3=$(setup_dir)
bash "$TAX"   init --project-root="$DIR3" >/dev/null
bash "$TAX"   set-vision "Helps freelance designers ship client work in under an hour." \
  --project-root="$DIR3" >/dev/null
bash "$TAX"   set-north-star "WAU" "100" "1000" "Q4 2026" --project-root="$DIR3" >/dev/null
bash "$DEFST" init --project-root="$DIR3" --define-mode=story --codebase-mode=greenfield >/dev/null

WS=$(bash "$TAX" get-workspace --project-root="$DIR3")
WS_VISION=$(echo "$WS" | jq -r '.vision // ""')
WS_METRIC=$(echo "$WS" | jq -r '.north_star.metric // ""')
WS_CURRENT=$(echo "$WS" | jq -r '.north_star.current // ""')
WS_TARGET=$(echo "$WS" | jq -r '.north_star.target // ""')
WS_HORIZON=$(echo "$WS" | jq -r '.north_star.horizon // ""')

[ -n "$WS_VISION" ] && [ -n "$WS_METRIC" ] \
  && ok "8.1 taxonomy carries vision + metric" \
  || ko "8.1" "missing source"

bash "$DEFST" set vision             "$WS_VISION"  --project-root="$DIR3"
bash "$DEFST" set north_star_metric  "$WS_METRIC"  --project-root="$DIR3"
bash "$DEFST" set north_star_current "$WS_CURRENT" --project-root="$DIR3"
bash "$DEFST" set north_star_target  "$WS_TARGET"  --project-root="$DIR3"
bash "$DEFST" set target_horizon     "$WS_HORIZON" --project-root="$DIR3"

DST_FILE="${DIR3}/.snap/.define-state.json"
[ "$(jq -r '.vision'             "$DST_FILE")" = "$WS_VISION"  ] \
  && ok "8.2 define-state.vision mirrors taxonomy" || ko "8.2" "drift"
[ "$(jq -r '.north_star_metric'  "$DST_FILE")" = "$WS_METRIC"  ] \
  && ok "8.3 define-state.north_star_metric mirrors taxonomy" || ko "8.3" "drift"
[ "$(jq -r '.north_star_current' "$DST_FILE")" = "$WS_CURRENT" ] \
  && ok "8.4 north_star_current mirrored" || ko "8.4" "drift"
[ "$(jq -r '.north_star_target'  "$DST_FILE")" = "$WS_TARGET"  ] \
  && ok "8.5 north_star_target mirrored"  || ko "8.5" "drift"
[ "$(jq -r '.target_horizon'     "$DST_FILE")" = "$WS_HORIZON" ] \
  && ok "8.6 target_horizon mirrored"     || ko "8.6" "drift"

# Wipe should clear define-state but leave taxonomy untouched.
bash "$DEFST" wipe --project-root="$DIR3" >/dev/null
[ ! -f "$DST_FILE" ] && ok "8.7 wipe removed define-state" || ko "8.7" "still there"
F3="${DIR3}/.snap/manifests/_taxonomy.json"
[ "$(jq -r '.workspace.vision' "$F3")" = "$WS_VISION" ] \
  && ok "8.8 wipe preserved taxonomy.workspace.vision" || ko "8.8" "vision lost"

trash "$DIR3" 2>/dev/null || true

# 9. SNAP_TAXONOMY_FILE redirect (N7 — runtime cache atomic edits)
echo ""
echo "[9] SNAP_TAXONOMY_FILE redirect"
DIR4=$(setup_dir)
bash "$TAX" init --project-root="$DIR4" >/dev/null
REAL="${DIR4}/.snap/manifests/_taxonomy.json"
ORIGINAL_VISION="initial vision long enough to satisfy validators."
bash "$TAX" set-vision "$ORIGINAL_VISION" --project-root="$DIR4" >/dev/null

# Snapshot real file into runtime cache (mimic step-00-vision-edit Task A).
CACHE_BASE="${DIR4}/.snap/.runtime/define-vision-test"
mkdir -p "$CACHE_BASE"
cp "$REAL" "${CACHE_BASE}/_taxonomy.json"

# Run set-vision with env override — should hit the cache, NOT the real file.
SNAP_TAXONOMY_FILE="${CACHE_BASE}/_taxonomy.json" \
  bash "$TAX" set-vision "Edited in cache — must not leak to real file yet." \
  --project-root="$DIR4" >/dev/null

[ "$(jq -r '.workspace.vision' "$REAL")" = "$ORIGINAL_VISION" ] \
  && ok "9.1 real file unchanged during cache edit" || ko "9.1" "leak"
[ "$(jq -r '.workspace.vision' "${CACHE_BASE}/_taxonomy.json")" = "Edited in cache — must not leak to real file yet." ] \
  && ok "9.2 cache holds the edit" || ko "9.2" "cache empty"

# Simulate the F.5 atomic flush.
mv "${CACHE_BASE}/_taxonomy.json" "$REAL"
[ "$(jq -r '.workspace.vision' "$REAL")" = "Edited in cache — must not leak to real file yet." ] \
  && ok "9.3 flush applies cache to real file" || ko "9.3" "flush failed"

# Abort scenario: redirect set, never flushes → real file stays at flushed value.
SNAP_TAXONOMY_FILE="${CACHE_BASE}/_taxonomy.json" \
  bash "$TAX" init --project-root="$DIR4" >/dev/null
SNAP_TAXONOMY_FILE="${CACHE_BASE}/_taxonomy.json" \
  bash "$TAX" set-vision "Aborted edit — never flushed." \
  --project-root="$DIR4" >/dev/null
# user "interrupts" → drop cache, don't flush.
trash "$CACHE_BASE" 2>/dev/null || true
[ "$(jq -r '.workspace.vision' "$REAL")" = "Edited in cache — must not leak to real file yet." ] \
  && ok "9.4 abort leaves real file untouched" || ko "9.4" "drift"

trash "$DIR4" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
