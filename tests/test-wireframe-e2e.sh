#!/usr/bin/env bash
# E2E test for /wireframe pipeline (step-00 → step-04) using dry-run helpers.
#
# Simulates the orchestration documented in skills/wireframe/step-*.md without
# invoking real Frame0/AFFiNE MCP tools.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${ROOT}/skills/_shared/filter-ui-tickets.sh"
FRAME0="${ROOT}/skills/_shared/frame0-helper.sh"
DOCS="${ROOT}/skills/_shared/docs-adapter.sh"
RENDER="${ROOT}/skills/_shared/render-template.sh"
TICKETS_ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"
PROGRESS="${ROOT}/skills/_shared/progress.sh"
SETUP="${ROOT}/skills/_shared/setup-snap-dir.sh"
TEMPLATE="${ROOT}/skills/_shared/templates/docs-defaults/wireframes-gallery.md"
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

DIR=$(mktemp -d -t snap-wf-e2e-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

FEATURE_ID="01-auth"
bash "$SETUP" --project-root="$DIR" --feature-id="$FEATURE_ID" --feature-name="Auth" --lang=en >/dev/null

MANIFEST="${DIR}/.snap/manifests/${FEATURE_ID}.manifest.json"
TICKETS="${DIR}/.snap/tickets/${FEATURE_ID}.json"
WF_DIR="${DIR}/.snap/wireframes/${FEATURE_ID}"
mkdir -p "$WF_DIR"

# Seed manifest with PRD ref so step-03 can read it
jq '.refs.prd = {platform:"affine", page_id:"DRY-GLOBAL-0", url:"https://affine.example/prd-global", sync_status:"synced"}' \
  "$MANIFEST" > "$DIR/.m.tmp" && mv "$DIR/.m.tmp" "$MANIFEST"

echo "=== /wireframe E2E (dry-run) ==="
echo ""

# --- Setup tickets fixture ------------------------------------------------
cat > "$TICKETS" <<JSON
{
  "feature_id": "${FEATURE_ID}",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Build signup screen","status":"todo","files":["src/components/Signup.tsx"]},
    {"local_id":"t-002","title":"Verify email page","status":"todo","files":["src/pages/Verify.tsx"]},
    {"local_id":"t-003","title":"Show error modal","status":"todo","files":["src/components/ErrorModal.tsx"]},
    {"local_id":"t-004","title":"DB migration users","status":"todo","files":["db/001-users.sql"]}
  ]
}
JSON

# --- Step-01: filter UI tickets -------------------------------------------
echo "[step-01] filter UI tickets"
ui_json=$(bash "$FILTER" --tickets-file="$TICKETS")
ui_count=$(echo "$ui_json" | jq 'length')
assert_eq "01.1 3 UI tickets (excl. DB migration)" "3" "$ui_count"

hint1=$(echo "$ui_json" | jq -r '.[] | select(.local_id=="t-001").screen_hint')
assert_eq "01.2 t-001 hint = signup-screen" "signup-screen" "$hint1"

screens_json=$(echo "$ui_json" | jq '
  [.[] | {screen_id: .screen_hint, states: ["empty","filled"], local_id}]
  | group_by(.screen_id)
  | map({screen_id: .[0].screen_id, states: .[0].states, ui_tickets: [.[].local_id]})
')
screen_count=$(echo "$screens_json" | jq 'length')
assert_eq "01.3 screens manifest count" "3" "$screen_count"

draft_path="${DIR}/.snap/queues/${FEATURE_ID}.wireframes-draft.json"
echo "$ui_json" | jq --argjson screens "$screens_json" '{ui_tickets: ., screens: $screens}' > "$draft_path"
[ -f "$draft_path" ] && ok "01.4 wireframes-draft stashed in queues/" || ko "01.4" "missing draft"

bash "$PROGRESS" step --project-root="$DIR" --skill=wireframe --feature-id="$FEATURE_ID" \
  --step-num=01 --step-name=filter --status=ok >/dev/null

# --- Step-02: Frame0 dry-run loop -----------------------------------------
echo ""
echo "[step-02] Frame0 design (dry-run)"
pages_log=()
i=0
while IFS= read -r screen_id; do
  while IFS= read -r state; do
    i=$((i + 1))
    out=$(bash "$FRAME0" --action=create-page \
      --title="${screen_id} — ${state}" \
      --project-root="$DIR" --dry-run 2>&1)
    is_dry=$(echo "$out" | jq -r '.mode')
    [ "$is_dry" = "dry-run" ] || ko "02.create $screen_id/$state" "mode=$is_dry"

    png_path="${WF_DIR}/${screen_id}-${state}.png"
    printf '\x89PNG\r\n\x1a\n' > "$png_path"
    pages_log+=("DRY-${i}|${screen_id}|${state}|${png_path}")
  done < <(echo "$screens_json" | jq -r --arg sid "$screen_id" '.[] | select(.screen_id==$sid).states[]')
done < <(echo "$screens_json" | jq -r '.[].screen_id')

[ "${#pages_log[@]}" = "6" ] && ok "02.1 6 pages created (3 screens × 2 states)" || ko "02.1" "got ${#pages_log[@]}"

all_exist=true
for line in "${pages_log[@]}"; do
  p="${line##*|}"
  [ -f "$p" ] || all_exist=false
done
[ "$all_exist" = "true" ] && ok "02.2 every PNG written" || ko "02.2" "some PNGs missing"

draft_with_pages=$(jq --argjson pages "$(printf '%s\n' "${pages_log[@]}" | jq -R 'split("|") | {frame0_page_id:.[0], screen_id:.[1], state:.[2], png_path:.[3]}' | jq -s .)" '
  .screens |= map(. as $s | .pages = ($pages | map(select(.screen_id == $s.screen_id) | {state, frame0_page_id, png_path})))
' "$draft_path")
echo "$draft_with_pages" > "$draft_path"

bash "$PROGRESS" step --project-root="$DIR" --skill=wireframe --feature-id="$FEATURE_ID" \
  --step-num=02 --step-name=design --status=ok >/dev/null

# --- Step-03: render gallery + dry-run docs publish -----------------------
echo ""
echo "[step-03] gallery render + publish (dry-run)"

ctx=$(jq -n \
  --arg fid "$FEATURE_ID" \
  --arg ftitle "Auth" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg dir ".snap/wireframes/${FEATURE_ID}" \
  --argjson screens "$(echo "$draft_with_pages" | jq '.screens')" '
  {
    product_name: "TestApp",
    updated_at: $now,
    frame0_export_dir: $dir,
    feature_id: $fid,
    features: [{
      feature_id: $fid,
      feature_title: $ftitle,
      screens: ($screens | map({
        screen_id: .screen_id,
        screen_title: .screen_id,
        screen_image_path: ((.pages // [])[0].png_path // ""),
        screen_states: (.states | join(", ")),
        screen_ctas: "—",
        screen_tickets: "—",
        screen_notes: "—"
      }))
    }],
    screen_index: ($screens | map(. as $s | (.pages // []) | map({screen_id: $s.screen_id, feature_id: $fid, state, path: .png_path})) | flatten)
  }')

gallery_md="${WF_DIR}/gallery.md"
bash "$RENDER" --template="$TEMPLATE" --vars="$ctx" > "$gallery_md"

[ -s "$gallery_md" ] && ok "03.1 gallery md non-empty" || ko "03.1" "empty"
grep -q "signup-screen" "$gallery_md" && ok "03.2 contains signup-screen" || ko "03.2" "missing signup"
grep -q "verify-screen" "$gallery_md" && ok "03.3 contains verify-screen" || ko "03.3" "missing verify"
grep -q "modal-section" "$gallery_md" && ok "03.4 contains modal-section" || ko "03.4" "missing modal"

PRD_PAGE_ID=$(jq -r '.refs.prd.page_id' "$MANIFEST")
publish_out=$(bash "$DOCS" --action=create --platform=affine \
  --parent-id="$PRD_PAGE_ID" \
  --title="Wireframes — Auth" \
  --content-file="$gallery_md" \
  --project-root="$DIR" --dry-run 2>&1)
publish_mode=$(echo "$publish_out" | jq -r '.mode')
assert_eq "03.5 docs-adapter dry-run mode" "dry-run" "$publish_mode"

# Ack into manifest.refs.wireframes_gallery (simulate sync-push ack)
gallery_url="https://affine.example/feature/${FEATURE_ID}/wireframes"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq --arg url "$gallery_url" --arg ts "$NOW" \
  '.refs.wireframes_gallery = {platform:"affine", page_id:"DRY-WF-0", url:$url, synced_at:$ts, sync_status:"synced"}' \
  "$MANIFEST" > "$DIR/.m.tmp" && mv "$DIR/.m.tmp" "$MANIFEST"

bash "$PROGRESS" step --project-root="$DIR" --skill=wireframe --feature-id="$FEATURE_ID" \
  --step-num=03 --step-name=gallery --status=ok >/dev/null

# --- Step-04: link tickets ------------------------------------------------
echo ""
echo "[step-04] link wireframes into tickets/{id}.json"

while IFS= read -r entry; do
  lid=$(echo "$entry" | jq -r '.local_id')
  sid=$(echo "$entry" | jq -r '.screen_hint')
  url="${gallery_url}#${sid}"
  jq --arg lid "$lid" --arg sid "$sid" --arg url "$url" \
    '(.tickets[] | select(.local_id == $lid))
       |= (.wireframe_screen = $sid | .wireframe_url = $url)' \
    "$TICKETS" > "$DIR/.t.tmp" && mv "$DIR/.t.tmp" "$TICKETS"
done < <(echo "$ui_json" | jq -c '.[]')

linked=$(jq '[.tickets[] | select(.wireframe_screen != null and .wireframe_url != null)] | length' "$TICKETS")
assert_eq "04.1 3 tickets linked" "3" "$linked"

t4_ws=$(jq -r '[.tickets[] | select(.local_id=="t-004")][0].wireframe_screen // "null"' "$TICKETS")
assert_eq "04.2 t-004 (non-UI) untouched" "null" "$t4_ws"

t1_url=$(jq -r '.tickets[] | select(.local_id=="t-001").wireframe_url' "$TICKETS")
case "$t1_url" in
  *"#signup-screen") ok "04.3 t-001 url anchored to screen" ;;
  *) ko "04.3" "url=$t1_url" ;;
esac

if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "$TICKETS" --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "04.4 tickets.json valid post-link"
  else
    ko "04.4" "ajv rejected"
  fi
else
  echo "  SKIP  04.4 ajv not installed"
fi

trash "$draft_path" 2>/dev/null || true
[ ! -f "$draft_path" ] && ok "04.5 draft cleaned up" || ko "04.5" "draft remains"

bash "$PROGRESS" step --project-root="$DIR" --skill=wireframe --feature-id="$FEATURE_ID" \
  --step-num=04 --step-name=link --status=ok >/dev/null
bash "$PROGRESS" finish --project-root="$DIR" --skill=wireframe --feature-id="$FEATURE_ID" --status=ok >/dev/null

# --- progress.json final state --------------------------------------------
echo ""
echo "[progress] in_flight purged after finish"
in_flight=$(bash "$PROGRESS" list --project-root="$DIR")
remaining=$(echo "$in_flight" | jq '[.[] | select(.skill == "wireframe" and .feature_id == "01-auth")] | length')
assert_eq "progress.1 wireframe entry purged" "0" "$remaining"

# --- Manifest state -------------------------------------------------------
gallery_synced=$(jq -r '.refs.wireframes_gallery.sync_status' "$MANIFEST")
assert_eq "manifest.1 refs.wireframes_gallery.sync_status=synced" "synced" "$gallery_synced"

# --- Idempotence: re-run step-04 should be no-op --------------------------
echo ""
echo "[idempotence] re-run link"
before=$(sha1sum "$TICKETS" | awk '{print $1}')
while IFS= read -r entry; do
  lid=$(echo "$entry" | jq -r '.local_id')
  sid=$(echo "$entry" | jq -r '.screen_hint')
  url="${gallery_url}#${sid}"
  jq --arg lid "$lid" --arg sid "$sid" --arg url "$url" \
    '(.tickets[] | select(.local_id == $lid))
       |= (.wireframe_screen = $sid | .wireframe_url = $url)' \
    "$TICKETS" > "$DIR/.t.tmp" && mv "$DIR/.t.tmp" "$TICKETS"
done < <(echo "$ui_json" | jq -c '.[]')
after=$(sha1sum "$TICKETS" | awk '{print $1}')
assert_eq "idem.1 second link is no-op" "$before" "$after"

[ -f "$TICKETS_ADAPTER" ] && ok "ref tickets-adapter present" || ko "ref" "missing"

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
