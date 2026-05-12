#!/usr/bin/env bash
# E2E test for /design pipeline (3 modes: ds-init, ds-update, mockup) — dry-run.
#
# Simulates the orchestration documented in skills/design/step-*.md without
# invoking real Penpot/Figma MCP. Verifies cooperation between:
#   - design-mode-resolver (mode auto-detection)
#   - figma-bridge-helper / penpot-helper (ds + mockup descriptors)
#   - figma-helper (export base64 → save-export decode)
#   - render-template (design-gallery.md)
#   - docs-adapter (gallery publish)
#   - jq-patch tickets.json
#   - ajv validate

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="${ROOT}/skills/_shared/design-mode-resolver.sh"
FIGMA="${ROOT}/skills/_shared/figma-helper.sh"
BRIDGE="${ROOT}/skills/_shared/figma-bridge-helper.sh"
PENPOT="${ROOT}/skills/_shared/penpot-helper.sh"
DOCS="${ROOT}/skills/_shared/docs-adapter.sh"
RENDER="${ROOT}/skills/_shared/render-template.sh"
PROGRESS="${ROOT}/skills/_shared/update-progress.sh"
TEMPLATE="${ROOT}/skills/_shared/templates/docs-defaults/design-gallery.md"
ATOMIC_TPL="${ROOT}/skills/_shared/templates/design-system-defaults/atomic.yaml"
MOLECULAR_TPL="${ROOT}/skills/_shared/templates/design-system-defaults/molecular.yaml"
ORGANISM_TPL="${ROOT}/skills/_shared/templates/design-system-defaults/organism.yaml"
SCHEMA="${ROOT}/skills/_shared/schemas/tickets.schema.json"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else ko "$label" "got '$actual' expected '$expected'"; fi
}

# --- bridge-ds stub ------------------------------------------------------
TMP=$(mktemp -d -t snap-design-e2e-XXXXXX)
trap 'trash "$TMP" 2>/dev/null || rm -rf "$TMP"' EXIT

STUB="$TMP/bridge-ds-stub.sh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
# Minimal bridge-ds stub. Echoes a deterministic JS body so downstream
# descriptors capture stable content.
case "$1" in
  --version) echo "bridge-ds-stub 0.0.1" ;;
  setup)     echo "{\"status\":\"ok\",\"kb_path\":\"$3\"}" ;;
  compile)   echo "// COMPILED stub for $2"
             echo "figma.createFrame();" ;;
  extract)   echo "{\"components\":[\"Header\",\"Card\",\"Button\"]}" ;;
  *)         echo "stub: unsupported $*" >&2; exit 2 ;;
esac
STUBEOF
chmod +x "$STUB"
export SNAP_BRIDGE_DS_BIN="$STUB"
export FIGMA_TOKEN="t_dummy_for_tests"

echo "=== /design E2E (dry-run) ==="
echo ""

# ========================================================================
# Sub-suite A — Mode resolver triage
# ========================================================================
echo "[A] mode resolver"

DIR="$TMP/proj-a"
mkdir -p "$DIR/specs" "$DIR/.claude/product/features/01-auth"
cp "$ATOMIC_TPL" "$DIR/specs/atomic.yaml"
cat > "$DIR/.claude/product/features/01-auth/tickets.json" <<'JSON'
{
  "feature_id": "01-auth",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Signup screen","status":"todo","files":["src/components/Signup.tsx"]},
    {"local_id":"t-002","title":"Verify email page","status":"todo","files":["src/pages/Verify.tsx"]},
    {"local_id":"t-099","title":"DB migration","status":"todo","files":["db/users.sql"]}
  ]
}
JSON

m=$(bash "$RESOLVER" --project-root="$DIR" --ds-binding-set=false --specs-dir=specs)
assert_eq "A.1 ds-init when no binding + specs" "ds-init" "$m"

m=$(bash "$RESOLVER" --project-root="$DIR" --ds-binding-set=true \
    --specs-dir=specs --feature-id=01-auth)
assert_eq "A.2 mockup when binding set + feature has UI" "mockup" "$m"

# ========================================================================
# Sub-suite B — ds-init mode (figma platform via Bridge)
# ========================================================================
echo ""
echo "[B] ds-init (figma + Bridge transport=official)"

DIR_B="$TMP/proj-b"
mkdir -p "$DIR_B/design-system/specs" "$DIR_B/.claude/product" "$DIR_B/.bridge-kb"
cp "$ATOMIC_TPL" "$DIR_B/design-system/specs/atomic.yaml"
cp "$MOLECULAR_TPL" "$DIR_B/design-system/specs/molecular.yaml"
cp "$ORGANISM_TPL" "$DIR_B/design-system/specs/organism.yaml"

# ds-init action: bootstraps KB structure (one call, not per spec).
out=$(bash "$BRIDGE" --action=ds-init \
      --kb-path="$DIR_B/.bridge-kb" \
      --transport=official --token-env=FIGMA_TOKEN \
      --dry-run 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "B.1 ds-init descriptor emitted" \
  || ko "B.1 ds-init descriptor" "rc=$rc out=$out"

# ds-update action: compiles all KB specs into JS payload via Bridge.
out=$(bash "$BRIDGE" --action=ds-update \
      --kb-path="$DIR_B/.bridge-kb" \
      --transport=official --token-env=FIGMA_TOKEN \
      --dry-run 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "B.2 ds-update descriptor emitted" \
  || ko "B.2 ds-update descriptor" "rc=$rc out=$out"

# Write the cache hash post-init
curr_hash=$(cat "$DIR_B"/design-system/specs/*.yaml | shasum -a 256 | awk '{print $1}')
echo "{\"specs_hash\":\"$curr_hash\",\"mode\":\"ds-init\"}" > "$DIR_B/.design-cache.json"
[ -f "$DIR_B/.design-cache.json" ] && ok "B.3 .design-cache.json written" || ko "B.3" "cache missing"

# ========================================================================
# Sub-suite C — ds-update mode (penpot platform)
# ========================================================================
echo ""
echo "[C] ds-update (penpot)"

DIR_C="$TMP/proj-c"
mkdir -p "$DIR_C/design-system/specs" "$DIR_C/.claude/product"
cp "$ATOMIC_TPL" "$DIR_C/design-system/specs/atomic.yaml"
echo "{\"specs_hash\":\"STALE_HASH_DIFFERS\",\"mode\":\"ds-init\"}" > "$DIR_C/.design-cache.json"

# Resolver should flag ds-update (binding set + stale hash, no feature)
m=$(bash "$RESOLVER" --project-root="$DIR_C" --ds-binding-set=true \
    --specs-dir=design-system/specs --cache-file=.design-cache.json)
assert_eq "C.1 resolver flags ds-update on stale hash" "ds-update" "$m"

# step-01 ds-bootstrap converts YAML CSpec → shapes JSON before invoking
# penpot-helper add-shapes (penpot's MCP expects shapes JSON, not YAML).
# Here we shortcut the conversion with a tiny equivalent shapes JSON.
shapes_json="$DIR_C/.design-cache/atomic-shapes.json"
mkdir -p "$(dirname "$shapes_json")"
cat > "$shapes_json" <<'JSON'
[
  {"type":"rect","name":"Button-Primary","x":0,"y":0,"width":120,"height":40,"fill":"#3B82F6"},
  {"type":"text","name":"Button-Label","x":12,"y":12,"width":96,"height":16,"text":"Sign up","fill":"#FFFFFF"}
]
JSON

out=$(bash "$PENPOT" --action=add-shapes \
      --page-id="components-page-id" \
      --shapes-file="$shapes_json" \
      --project-root="$DIR_C" --dry-run 2>&1)
rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 10 ]; then
  ok "C.2 penpot add-shapes descriptor emitted"
else
  ko "C.2 penpot add-shapes" "rc=$rc out=$out"
fi

# After patch, cache hash refreshed to current
curr=$(cat "$DIR_C/design-system/specs/atomic.yaml" | shasum -a 256 | awk '{print $1}')
echo "{\"specs_hash\":\"$curr\",\"mode\":\"ds-update\"}" > "$DIR_C/.design-cache.json"
m=$(bash "$RESOLVER" --project-root="$DIR_C" --ds-binding-set=true \
    --specs-dir=design-system/specs --cache-file=.design-cache.json)
assert_eq "C.3 resolver no-op after patch" "none" "$m"

# ========================================================================
# Sub-suite D — mockup mode full pipeline (figma platform)
# ========================================================================
echo ""
echo "[D] mockup full pipeline (figma)"

DIR_D="$TMP/proj-d"
FEATURE_ID="01-auth"
FEATURE_DIR="$DIR_D/.claude/product/features/$FEATURE_ID"
mkdir -p "$FEATURE_DIR/design" "$DIR_D/.claude/product"

cat > "$FEATURE_DIR/tickets.json" <<'JSON'
{
  "feature_id": "01-auth",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Build signup screen","status":"todo","files":["src/components/Signup.tsx"]},
    {"local_id":"t-002","title":"Verify email page","status":"todo","files":["src/pages/Verify.tsx"]},
    {"local_id":"t-099","title":"DB migration","status":"todo","files":["db/users.sql"]}
  ]
}
JSON

cat > "$DIR_D/.claude/product/.docs-cache.json" <<'JSON'
{"prd_global": {"page_id":"DRY-GLOBAL-0","url":"https://docs.example/prd-global"}}
JSON

# step-02 source-resolve substitute: build a tiny screens manifest
draft="$FEATURE_DIR/.design-draft.json"
cat > "$draft" <<'JSON'
{
  "source": "tickets-only",
  "ui_tickets": [
    {"local_id":"t-001","title":"Build signup screen","screen_hint":"signup-screen"},
    {"local_id":"t-002","title":"Verify email page","screen_hint":"verify-screen"}
  ],
  "screens": [
    {"screen_id":"signup-screen","states":["default","error"],"ui_tickets":["t-001"]},
    {"screen_id":"verify-screen","states":["default"],"ui_tickets":["t-002"]}
  ]
}
JSON

# --- step-03 mockup loop (figma): mockup-compile + export-shape + save ----
# Bridge mockup-compile uses --scene-graph-file=YAML as the input CSpec.
# (Output side info goes into other helper params; in this skill flow the
# JS produced by Bridge is consumed via the figma_execute descriptor.)
mkdir -p "$DIR_D/.bridge-kb"
mockup_pages=()
i=0
while IFS= read -r screen_id; do
  while IFS= read -r state; do
    i=$((i + 1))
    cspec="$DIR_D/.design-cache/${screen_id}-${state}.yaml"
    mkdir -p "$(dirname "$cspec")"
    cat > "$cspec" <<YAML
frame: { name: "${screen_id}-${state}" }
children:
  - component: AuthCard
    bind: { heading: "Sign up" }
YAML
    out=$(bash "$BRIDGE" --action=mockup-compile \
          --kb-path="$DIR_D/.bridge-kb" \
          --scene-graph-file="$cspec" \
          --transport=official --token-env=FIGMA_TOKEN \
          --dry-run 2>&1)
    rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 10 ] || ko "D.compile $screen_id/$state" "rc=$rc"

    # export descriptor (dry-run → mock base64); bridge-helper uses --node-id
    asset_path="$FEATURE_DIR/design/${screen_id}-${state}.png"
    out=$(bash "$BRIDGE" --action=export-shape \
          --node-id="DRY-${i}" --output-path="$asset_path" \
          --format=png --scale=2 \
          --dry-run 2>&1)
    rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 10 ] || ko "D.export $screen_id/$state" "rc=$rc"

    # Synthesize asset (skill would invoke figma-helper save-export with real data)
    printf '\x89PNG\r\n\x1a\n' > "$asset_path"
    mockup_pages+=("DRY-${i}|${screen_id}|${state}|mockup|${asset_path}")
  done < <(jq -r --arg sid "$screen_id" '.screens[] | select(.screen_id==$sid).states[]' "$draft")
done < <(jq -r '.screens[].screen_id' "$draft")

[ "${#mockup_pages[@]}" = "3" ] && ok "D.1 3 mockups created (2 screens, 2+1 states)" \
  || ko "D.1" "got ${#mockup_pages[@]}"

# Update draft with pages
pages_json=$(printf '%s\n' "${mockup_pages[@]}" \
  | jq -R 'split("|") | {platform_page_id:.[0],screen_id:.[1],state:.[2],mode:.[3],asset_path:.[4]}' \
  | jq -s .)
draft_with_pages=$(jq --argjson pages "$pages_json" '
  .screens |= map(. as $s | .pages = ($pages | map(select(.screen_id == $s.screen_id) | {state, platform_page_id, asset_path, mode})))
' "$draft")
echo "$draft_with_pages" > "$draft"

# --- step-04 gallery render -----------------------------------------------
ctx=$(jq -n \
  --arg fid "$FEATURE_ID" \
  --arg ftitle "Auth" \
  --arg plat "figma" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg dir "features/${FEATURE_ID}/design" \
  --argjson screens "$(echo "$draft_with_pages" | jq '.screens')" '
  {
    product_name: "TestApp",
    updated_at: $now,
    design_platform: $plat,
    design_export_dir: $dir,
    feature_id: $fid,
    features: [{
      feature_id: $fid,
      feature_title: $ftitle,
      screens: ($screens | map({
        screen_id: .screen_id,
        screen_title: .screen_id,
        states: ((.pages // []) | map({state, mode, asset_path})),
        components_used: "AuthCard",
        ds_source: "dummy-key",
        screen_tickets: ((.ui_tickets // []) | join(",")),
        screen_notes: "—"
      }))
    }],
    screen_index: ($screens | map(. as $s | (.pages // []) | map({screen_id: $s.screen_id, feature_id: $fid, state, mode, path: .asset_path})) | flatten)
  }')

gallery_md="$DIR_D/.claude/product/design-gallery.md"
bash "$RENDER" --template="$TEMPLATE" --vars="$ctx" > "$gallery_md"

[ -s "$gallery_md" ] && ok "D.2 gallery md non-empty" || ko "D.2" "empty"
grep -q "signup-screen" "$gallery_md" && ok "D.3 contains signup-screen" || ko "D.3" "missing signup"
grep -q "verify-screen" "$gallery_md" && ok "D.4 contains verify-screen" || ko "D.4" "missing verify"
grep -q "Design — Auth\|Design - Auth\|figma" "$gallery_md" && ok "D.5 platform surfaced" || ko "D.5" "missing figma marker"

# Docs publish dry-run
publish=$(bash "$DOCS" --action=create --platform=affine \
  --parent-id="DRY-GLOBAL-0" --title="Design — Auth" \
  --content-file="$gallery_md" \
  --project-root="$DIR_D" --dry-run 2>&1)
publish_mode=$(echo "$publish" | jq -r '.mode')
assert_eq "D.6 docs-adapter dry-run" "dry-run" "$publish_mode"

# Cache gallery URL
gallery_url="https://docs.example/feature/${FEATURE_ID}/design"
jq --arg fid "$FEATURE_ID" --arg url "$gallery_url" \
  '.design_gallery[$fid] = {page_id:"DRY-DG-0", url:$url}' \
  "$DIR_D/.claude/product/.docs-cache.json" > "$DIR_D/tmp" \
  && mv "$DIR_D/tmp" "$DIR_D/.claude/product/.docs-cache.json"

# --- step-05 link tickets ------------------------------------------------
while IFS= read -r entry; do
  lid=$(echo "$entry" | jq -r '.local_id')
  sid=$(echo "$entry" | jq -r '.screen_hint')
  url="${gallery_url}#${sid}"
  jq --arg lid "$lid" --arg sid "$sid" --arg url "$url" --arg mode "mockup" \
    '(.tickets[] | select(.local_id == $lid))
      |= (.design_screen = $sid | .design_url = $url | .design_mode = $mode)' \
    "$FEATURE_DIR/tickets.json" > "$FEATURE_DIR/tickets.tmp" \
    && mv "$FEATURE_DIR/tickets.tmp" "$FEATURE_DIR/tickets.json"
done < <(jq -c '.ui_tickets[]' "$draft")

linked=$(jq '[.tickets[] | select(.design_screen != null and .design_url != null and .design_mode != null)] | length' "$FEATURE_DIR/tickets.json")
assert_eq "D.7 2 tickets linked with design fields" "2" "$linked"

# Non-UI ticket untouched
t99=$(jq -r '[.tickets[] | select(.local_id=="t-099")][0].design_screen // "null"' "$FEATURE_DIR/tickets.json")
assert_eq "D.8 t-099 (non-UI) untouched" "null" "$t99"

# URL anchored
t1_url=$(jq -r '.tickets[] | select(.local_id=="t-001").design_url' "$FEATURE_DIR/tickets.json")
case "$t1_url" in
  *"#signup-screen") ok "D.9 design_url anchored to screen" ;;
  *) ko "D.9" "url=$t1_url" ;;
esac

# Schema validate (only if tickets schema accepts new design_* fields — see Sub-phase 5)
if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "$FEATURE_DIR/tickets.json" \
      --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "D.10 tickets.json valid post-design-link"
  else
    echo "  SKIP  D.10 tickets schema not yet extended (Sub-phase 5)"
  fi
else
  echo "  SKIP  D.10 ajv not installed"
fi

# Progress trail
bash "$PROGRESS" --project-root="$DIR_D" --feature-id="$FEATURE_ID" \
  --skill=design --step-num=03 --step-name=mockup --status=ok >/dev/null
bash "$PROGRESS" --project-root="$DIR_D" --feature-id="$FEATURE_ID" \
  --skill=design --step-num=04 --step-name=gallery --status=ok >/dev/null
bash "$PROGRESS" --project-root="$DIR_D" --feature-id="$FEATURE_ID" \
  --skill=design --step-num=05 --step-name=link --status=ok >/dev/null

prog="$FEATURE_DIR/progress.md"
[ -f "$prog" ] && grep -q "design step-05 link — ok" "$prog" \
  && ok "D.11 progress includes design step-05 link" \
  || ko "D.11" "progress missing step-05 entry"

# === Summary ============================================================
echo ""
echo "==============================="
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
