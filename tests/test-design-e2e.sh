#!/usr/bin/env bash
# E2E test for /design pipeline (step-00 → step-04) using dry-run helpers.
#
# /design is mockup-only (v1.0.0). Same helpers as /wireframe (figma-helper.sh /
# penpot-helper.sh). Verifies cooperation: filter-ui-tickets → figma-helper
# → render gallery → docs-adapter create → jq-patch tickets/{id}.json → ajv.
#
# Sub-suite A — story-id scope. Sub-suite B — ticket-id scope.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${ROOT}/skills/_shared/filter-ui-tickets.sh"
FIGMA="${ROOT}/skills/_shared/figma-helper.sh"
DOCS="${ROOT}/skills/_shared/docs-adapter.sh"
RENDER="${ROOT}/skills/_shared/render-template.sh"
PROGRESS="${ROOT}/skills/_shared/progress.sh"
SETUP="${ROOT}/skills/_shared/setup-snap-dir.sh"
TEMPLATE="${ROOT}/skills/_shared/templates/docs-defaults/design-gallery.md"
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

TMP=$(mktemp -d -t snap-design-e2e-XXXXXX)
trap 'trash "$TMP" 2>/dev/null || true' EXIT

echo "=== /design E2E (dry-run) ==="
echo ""

# Shared fixture: one feature, 3 UI tickets + 1 non-UI ticket.
make_fixture() {
  local dir="$1"
  bash "$SETUP" --project-root="$dir" --story-id="01-auth" --story-name="Auth" --lang=en >/dev/null
  # Seed PRD ref so step-03 can use it as parent
  jq '.refs.prd = {platform:"affine", page_id:"DRY-GLOBAL-0", url:"https://docs.example/prd-global", sync_status:"synced"}' \
    "${dir}/.snap/manifests/01-auth.manifest.json" > "$dir/.m.tmp" \
    && mv "$dir/.m.tmp" "${dir}/.snap/manifests/01-auth.manifest.json"
  cat > "${dir}/.snap/tickets/01-auth.json" <<'JSON'
{
  "story_id": "01-auth",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Build signup screen","status":"todo","files":["src/components/Signup.tsx"]},
    {"local_id":"t-002","title":"Verify email page","status":"todo","files":["src/pages/Verify.tsx"]},
    {"local_id":"t-003","title":"Show error modal","status":"todo","files":["src/components/ErrorModal.tsx"]},
    {"local_id":"t-099","title":"DB migration users","status":"todo","files":["db/001-users.sql"]}
  ]
}
JSON
  mkdir -p "${dir}/.snap/designs/01-auth"
}

run_mockup_loop() {
  local dir="$1" design_dir="$2" screens_json="$3"
  local i=0 screen_id state out asset_path
  while IFS= read -r screen_id; do
    while IFS= read -r state; do
      i=$((i + 1))
      out=$(bash "$FIGMA" --action=create-page \
        --title="01-auth-${screen_id}-${state}" --dry-run 2>&1)
      [ "$(echo "$out" | jq -r '.mode')" = "dry-run" ] || { echo "create $screen_id/$state not dry-run" >&2; continue; }

      printf '[{"type":"rect","name":"frame","x":0,"y":0,"width":375,"height":812,"fill":"#FFFFFF"}]' \
        > "${dir}/.shapes-${screen_id}-${state}.json"
      out=$(bash "$FIGMA" --action=add-shapes \
        --page-id="DRY-${i}" \
        --shapes-file="${dir}/.shapes-${screen_id}-${state}.json" --dry-run 2>&1)
      [ "$(echo "$out" | jq -r '.mode')" = "dry-run" ] || { echo "add-shapes $screen_id/$state not dry-run" >&2; continue; }

      asset_path="${design_dir}/01-auth-${screen_id}-${state}.png"
      out=$(bash "$FIGMA" --action=export-png \
        --shape-id="DRY-${i}" --output-path="$asset_path" \
        --format=png --scale=2 --dry-run 2>&1)
      [ "$(echo "$out" | jq -r '.mode')" = "dry-run" ] || { echo "export $screen_id/$state not dry-run" >&2; continue; }

      printf '\x89PNG\r\n\x1a\n' > "$asset_path"
      echo "DRY-${i}|${screen_id}|${state}|mockup|${asset_path}"
    done < <(echo "$screens_json" | jq -r --arg sid "$screen_id" '.[] | select(.screen_id==$sid).states[]')
  done < <(echo "$screens_json" | jq -r '.[].screen_id')
}

# ========================================================================
# Sub-suite A — story-id scope
# ========================================================================
echo "[A] story-id scope — full pipeline (figma)"

DIR_A="$TMP/proj-a"
make_fixture "$DIR_A"
TICKETS_A="${DIR_A}/.snap/tickets/01-auth.json"
MANIFEST_A="${DIR_A}/.snap/manifests/01-auth.manifest.json"
DESIGN_DIR_A="${DIR_A}/.snap/designs/01-auth"
DRAFT_A="${DIR_A}/.snap/queues/01-auth.design-draft.json"

ui_json=$(bash "$FILTER" --tickets-file="$TICKETS_A")
ui_count=$(echo "$ui_json" | jq 'length')
assert_eq "A.1 3 UI tickets targeted (excl. DB migration)" "3" "$ui_count"

screens_a=$(echo "$ui_json" | jq '
  [.[] | {screen_id: .screen_hint, states: ["default","error"], local_id}]
  | group_by(.screen_id)
  | map({screen_id: .[0].screen_id, states: .[0].states, ui_tickets: [.[].local_id]})
')
assert_eq "A.2 3 screens in manifest" "3" "$(echo "$screens_a" | jq 'length')"

echo "$ui_json" | jq --argjson screens "$screens_a" \
  '{source:"tickets-only", target_tickets: [.[].local_id], ui_tickets: ., screens: $screens}' \
  > "$DRAFT_A"
[ -f "$DRAFT_A" ] && ok "A.3 design-draft stashed in queues/" || ko "A.3" "missing draft"
bash "$PROGRESS" step --project-root="$DIR_A" --skill=design --story-id="01-auth" \
  --step-num=01 --step-name=source-resolve --status=ok >/dev/null

pages_a=()
while IFS= read -r line; do pages_a+=("$line"); done < <(run_mockup_loop "$DIR_A" "$DESIGN_DIR_A" "$screens_a")
assert_eq "A.4 6 mockups created (3 screens × 2 states)" "6" "${#pages_a[@]}"

all_exist=true
for line in "${pages_a[@]}"; do [ -f "${line##*|}" ] || all_exist=false; done
[ "$all_exist" = "true" ] && ok "A.5 every asset written" || ko "A.5" "some assets missing"

draft_a_pages=$(jq --argjson pages "$(printf '%s\n' "${pages_a[@]}" \
  | jq -R 'split("|") | {platform_page_id:.[0],screen_id:.[1],state:.[2],mode:.[3],asset_path:.[4]}' \
  | jq -s .)" '
  .screens |= map(. as $s | .pages = ($pages | map(select(.screen_id == $s.screen_id) | {state, platform_page_id, asset_path, mode})))
' "$DRAFT_A")
echo "$draft_a_pages" > "$DRAFT_A"
bash "$PROGRESS" step --project-root="$DIR_A" --skill=design --story-id="01-auth" \
  --step-num=02 --step-name=mockup --status=ok >/dev/null

ctx=$(jq -n \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson screens "$(echo "$draft_a_pages" | jq '.screens')" '
  {
    product_name: "TestApp",
    updated_at: $now,
    design_platform: "figma",
    design_export_dir: ".snap/designs/01-auth",
    story_id: "01-auth",
    features: [{
      story_id: "01-auth",
      feature_title: "Auth",
      screens: ($screens | map({
        screen_id: .screen_id,
        screen_title: .screen_id,
        states: ((.pages // []) | map({state, mode, asset_path})),
        components_used: "AuthCard",
        ds_source: "none",
        screen_tickets: ((.ui_tickets // []) | join(",")),
        screen_notes: "—"
      }))
    }],
    screen_index: ($screens | map(. as $s | (.pages // []) | map({screen_id: $s.screen_id, story_id: "01-auth", state, mode, path: .asset_path})) | flatten)
  }')

gallery_md="${DESIGN_DIR_A}/gallery.md"
bash "$RENDER" --template="$TEMPLATE" --vars="$ctx" > "$gallery_md"
[ -s "$gallery_md" ] && ok "A.6 gallery md non-empty" || ko "A.6" "empty"
grep -q "signup-screen" "$gallery_md" && ok "A.7 gallery contains signup-screen" || ko "A.7" "missing signup"
grep -q "verify-screen" "$gallery_md" && ok "A.8 gallery contains verify-screen" || ko "A.8" "missing verify"

PRD_PAGE_ID=$(jq -r '.refs.prd.page_id' "$MANIFEST_A")
publish=$(bash "$DOCS" --action=create --platform=affine \
  --parent-id="$PRD_PAGE_ID" --title="Design — Auth" \
  --content-file="$gallery_md" --project-root="$DIR_A" --dry-run 2>&1)
assert_eq "A.9 docs-adapter dry-run" "dry-run" "$(echo "$publish" | jq -r '.mode')"

gallery_url="https://docs.example/feature/01-auth/design"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq --arg url "$gallery_url" --arg ts "$NOW" \
  '.refs.design_gallery = {platform:"affine", page_id:"DRY-DG-0", url:$url, synced_at:$ts, sync_status:"synced"}' \
  "$MANIFEST_A" > "$DIR_A/.m.tmp" && mv "$DIR_A/.m.tmp" "$MANIFEST_A"

bash "$PROGRESS" step --project-root="$DIR_A" --skill=design --story-id="01-auth" \
  --step-num=03 --step-name=gallery --status=ok >/dev/null

while IFS= read -r entry; do
  lid=$(echo "$entry" | jq -r '.local_id')
  sid=$(echo "$entry" | jq -r '.screen_hint')
  jq --arg lid "$lid" --arg sid "$sid" --arg url "${gallery_url}#${sid}" --arg mode "mockup" \
    '(.tickets[] | select(.local_id == $lid))
       |= (.design_screen = $sid | .design_url = $url | .design_mode = $mode)' \
    "$TICKETS_A" > "$DIR_A/.t.tmp" && mv "$DIR_A/.t.tmp" "$TICKETS_A"
done < <(echo "$ui_json" | jq -c '.[]')

linked=$(jq '[.tickets[] | select(.design_screen != null and .design_url != null and .design_mode != null)] | length' "$TICKETS_A")
assert_eq "A.10 3 tickets linked with design fields" "3" "$linked"

t99=$(jq -r '[.tickets[] | select(.local_id=="t-099")][0].design_screen // "null"' "$TICKETS_A")
assert_eq "A.11 t-099 (non-UI) untouched" "null" "$t99"

t1_url=$(jq -r '.tickets[] | select(.local_id=="t-001").design_url' "$TICKETS_A")
case "$t1_url" in
  *"#signup-screen") ok "A.12 design_url anchored to screen" ;;
  *) ko "A.12" "url=$t1_url" ;;
esac

if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "$TICKETS_A" --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "A.13 tickets.json valid post-design-link"
  else
    ko "A.13" "ajv rejected"
  fi
else
  echo "  SKIP  A.13 ajv not installed"
fi

bash "$PROGRESS" step --project-root="$DIR_A" --skill=design --story-id="01-auth" \
  --step-num=04 --step-name=link --status=ok >/dev/null

# Verify progress.json contains link step
link_ok=$(bash "$PROGRESS" list --project-root="$DIR_A" \
  | jq '[.[] | select(.skill == "design" and .story_id == "01-auth") | .steps[] | select(.name == "link" and .status == "ok")] | length')
[ "$link_ok" -ge 1 ] && ok "A.14 progress includes design step-04 link" || ko "A.14" "progress missing step-04 entry"

# ========================================================================
# Sub-suite B — ticket-id scope
# ========================================================================
echo ""
echo "[B] ticket-id scope — single ticket (figma)"

DIR_B="$TMP/proj-b"
make_fixture "$DIR_B"
TICKETS_B="${DIR_B}/.snap/tickets/01-auth.json"
DESIGN_DIR_B="${DIR_B}/.snap/designs/01-auth"

ui_all=$(bash "$FILTER" --tickets-file="$TICKETS_B")
ui_one=$(echo "$ui_all" | jq '[.[] | select(.local_id=="t-001")]')
assert_eq "B.1 single ticket targeted" "1" "$(echo "$ui_one" | jq 'length')"

screens_b=$(echo "$ui_one" | jq '
  [.[] | {screen_id: .screen_hint, states: ["default"], local_id}]
  | group_by(.screen_id)
  | map({screen_id: .[0].screen_id, states: .[0].states, ui_tickets: [.[].local_id]})
')
assert_eq "B.2 1 screen in manifest" "1" "$(echo "$screens_b" | jq 'length')"

pages_b=()
while IFS= read -r line; do pages_b+=("$line"); done < <(run_mockup_loop "$DIR_B" "$DESIGN_DIR_B" "$screens_b")
assert_eq "B.3 1 mockup created" "1" "${#pages_b[@]}"

gallery_url_b="https://docs.example/feature/01-auth/design"
while IFS= read -r entry; do
  lid=$(echo "$entry" | jq -r '.local_id')
  sid=$(echo "$entry" | jq -r '.screen_hint')
  jq --arg lid "$lid" --arg sid "$sid" --arg url "${gallery_url_b}#${sid}" --arg mode "mockup" \
    '(.tickets[] | select(.local_id == $lid))
       |= (.design_screen = $sid | .design_url = $url | .design_mode = $mode)' \
    "$TICKETS_B" > "$DIR_B/.t.tmp" && mv "$DIR_B/.t.tmp" "$TICKETS_B"
done < <(echo "$ui_one" | jq -c '.[]')

linked_b=$(jq '[.tickets[] | select(.design_url != null)] | length' "$TICKETS_B")
assert_eq "B.4 only the targeted ticket linked" "1" "$linked_b"

t2_b=$(jq -r '[.tickets[] | select(.local_id=="t-002")][0].design_url // "null"' "$TICKETS_B")
assert_eq "B.5 non-targeted UI ticket untouched" "null" "$t2_b"

before=$(sha1sum "$TICKETS_B" | awk '{print $1}')
while IFS= read -r entry; do
  lid=$(echo "$entry" | jq -r '.local_id')
  sid=$(echo "$entry" | jq -r '.screen_hint')
  jq --arg lid "$lid" --arg sid "$sid" --arg url "${gallery_url_b}#${sid}" --arg mode "mockup" \
    '(.tickets[] | select(.local_id == $lid))
       |= (.design_screen = $sid | .design_url = $url | .design_mode = $mode)' \
    "$TICKETS_B" > "$DIR_B/.t.tmp" && mv "$DIR_B/.t.tmp" "$TICKETS_B"
done < <(echo "$ui_one" | jq -c '.[]')
after=$(sha1sum "$TICKETS_B" | awk '{print $1}')
assert_eq "B.6 second link is a no-op" "$before" "$after"

echo ""
echo "==============================="
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
