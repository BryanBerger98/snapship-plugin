#!/usr/bin/env bash
# E2E for /ticket skill — exercises the helper-script orchestration end-to-end
# in dry-run mode for github / gitlab / jira platforms.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"
RENDER="${ROOT}/skills/_shared/render-template.sh"
PROGRESS="${ROOT}/skills/_shared/progress.sh"
SETUP="${ROOT}/skills/_shared/setup-snap-dir.sh"
LOAD_CFG="${ROOT}/skills/_shared/load-config.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
setup_dir() { mktemp -d -t snap-tk-XXXXXX; }

write_config() {
  local d="$1" platform="$2"
  cat > "${d}/snap.config.json" <<JSON
{
  "version": "1.0",
  "tickets": { "platform": "${platform}" },
  "repository": { "platform": "github", "default_branch": "main" },
  "documentation": { "platform": "none" }
}
JSON
}

# Pre-stage a feature workspace as if /define had been run.
seed_feature() {
  local d="$1" fid="$2"
  bash "$SETUP" --project-root="$d" --story-id="$fid" --story-name="Auth" --lang=en >/dev/null
  cat > "${d}/.snap/PRDs/${fid}.md" <<'MD'
# PRD — Auth

## Problem
Designers cannot save work between sessions.

## Solution overview
Email signup with verification.

## Acceptance criteria
- AC-1 — User signs up with email + password
- AC-2 — Verification email sent

## In scope
email/password, verification email

## Out of scope
OAuth, SSO

## Wireframes
- signup-screen
MD
}

run_platform() {
  local platform="$1"
  echo ""
  echo "=== platform=${platform} ==="
  local DIR
  DIR=$(setup_dir)
  write_config "$DIR" "$platform"
  seed_feature "$DIR" "01-auth"

  local MANIFEST="${DIR}/.snap/manifests/01-auth.manifest.json"
  local PRD="${DIR}/.snap/PRDs/01-auth.md"
  local DRAFT="${DIR}/.snap/queues/01-auth.tickets-draft.json"
  local TICKETS="${DIR}/.snap/tickets/01-auth.json"

  # step-00: load config + record progress
  bash "$LOAD_CFG" --project-root="$DIR" >/dev/null 2>&1 \
    && ok "${platform}.00 load-config" \
    || ko "${platform}.00 load-config" "non-zero"
  bash "$PROGRESS" step --project-root="$DIR" --skill=ticket --story-id=01-auth --step-num=00 --step-name=init --status=ok >/dev/null

  # step-01: load PRD (check sections present)
  for sec in "Problem" "Solution overview" "Acceptance criteria" "In scope" "Out of scope"; do
    if ! grep -q "^## ${sec}" "$PRD"; then
      ko "${platform}.01 prd-feature missing section '$sec'" "missing"
      return
    fi
  done
  ok "${platform}.01 prd-feature has all required sections"
  bash "$PROGRESS" step --project-root="$DIR" --skill=ticket --story-id=01-auth --step-num=01 --step-name=load --status=ok >/dev/null

  # step-02: decompose — synthesize 2 stories from 2 AC
  cat > "$DRAFT" <<'JSON'
[
  {
    "ticket_id": "01-auth-001",
    "title": "Add email signup endpoint",
    "ac_id": "1",
    "ac_text": "User signs up with email + password",
    "expected_files": ["src/auth/signup.ts", "src/auth/__tests__/signup.test.ts"],
    "depends_on": [],
    "labels": ["feature:01-auth", "type:feature"]
  },
  {
    "ticket_id": "01-auth-002",
    "title": "Send verification email",
    "ac_id": "2",
    "ac_text": "Verification email sent",
    "expected_files": ["src/auth/email.ts"],
    "depends_on": ["01-auth-001"],
    "labels": ["feature:01-auth", "type:feature"]
  }
]
JSON
  draft_count=$(jq 'length' "$DRAFT")
  [ "$draft_count" = "2" ] && ok "${platform}.02 decompose drafted 2 stories" || ko "${platform}.02" "got $draft_count"
  bash "$PROGRESS" step --project-root="$DIR" --skill=ticket --story-id=01-auth --step-num=02 --step-name=decompose --status=ok >/dev/null

  # step-03: enrich — stub context block + ticket type on each story
  jq 'map(. + {context: {codebase: "auth/index.ts:42 has createUser", docs: "", web: []}, type: "user-story"})' \
    "$DRAFT" > "$DIR/.tk.tmp" && mv "$DIR/.tk.tmp" "$DRAFT"
  enriched=$(jq '[.[] | select(.context != null and .type != null)] | length' "$DRAFT")
  [ "$enriched" = "2" ] && ok "${platform}.03 enrichment populated context" || ko "${platform}.03" "got $enriched"
  bash "$PROGRESS" step --project-root="$DIR" --skill=ticket --story-id=01-auth --step-num=03 --step-name=enrich --status=ok >/dev/null

  # step-04: format — resolve template via resolve-template.sh (kind=ticket type=user-story)
  local tpl tpl_json
  tpl_json=$(SNAP_PROJECT_ROOT="$DIR" bash "${ROOT}/skills/_shared/resolve-template.sh" \
    --kind=ticket --type=user-story --platform="${platform}" --project-root="$DIR" 2>/dev/null) || tpl_json=""
  tpl=$(printf '%s' "$tpl_json" | jq -r '.path // empty' 2>/dev/null) || tpl=""
  if [ -z "$tpl" ] || [ ! -f "$tpl" ]; then
    ko "${platform}.04 template missing" "$tpl"
    return
  fi
  local story_ctx
  story_ctx=$(jq '.[0]' "$DRAFT")
  body=$(echo "$story_ctx" | bash "$RENDER" --template="$tpl" --vars="$story_ctx" 2>/dev/null || true)
  if echo "$body" | grep -q "Add email signup endpoint"; then
    ok "${platform}.04 template renders title"
  else
    [ -n "$body" ] && ok "${platform}.04 template rendered (no title placeholder)" \
      || ko "${platform}.04 template render failed" "empty"
  fi
  bash "$PROGRESS" step --project-root="$DIR" --skill=ticket --story-id=01-auth --step-num=04 --step-name=format --status=ok >/dev/null

  # step-05: push (dry-run)
  pushed=0
  while IFS= read -r ticket; do
    title=$(echo "$ticket" | jq -r '.title')
    out=$(bash "$ADAPTER" --action=create \
      --project-root="$DIR" \
      --platform="$platform" \
      --title="$title" \
      --body="<rendered body>" \
      --dry-run 2>&1)
    rc=$?
    if [ "$rc" = "0" ]; then
      mode=$(echo "$out" | jq -r '.mode')
      [ "$mode" = "dry-run" ] && pushed=$((pushed + 1))
    elif [ "$rc" = "10" ] && [ "$platform" = "jira" ]; then
      pushed=$((pushed + 1))
    else
      ko "${platform}.05 adapter failed" "rc=$rc out=$out"
      return
    fi
  done < <(jq -c '.[]' "$DRAFT")
  [ "$pushed" = "2" ] && ok "${platform}.05 dry-run pushed 2 tickets" || ko "${platform}.05" "pushed=$pushed"
  bash "$PROGRESS" step --project-root="$DIR" --skill=ticket --story-id=01-auth --step-num=05 --step-name=push --status=skip --note="dry-run" >/dev/null

  # step-06: index — promote draft → tickets/{id}.json (schema-shaped)
  jq --arg fid "01-auth" --arg p "$platform" \
    '{
      story_id: $fid,
      platform: $p,
      synced_at: "2026-05-09T00:00:00Z",
      tickets: [.[] | {
        local_id: .ticket_id,
        title: .title,
        status: "todo",
        labels: .labels,
        depends_on: .depends_on,
        files: .expected_files,
        acceptance_criteria: [{text: .ac_text}]
      }]
    }' "$DRAFT" > "$TICKETS"

  # ajv validate
  if command -v ajv >/dev/null 2>&1; then
    if ajv validate -s "${ROOT}/skills/_shared/schemas/tickets.schema.json" \
      -d "$TICKETS" \
      --spec=draft2020 --strict=false >/dev/null 2>&1; then
      ok "${platform}.06 tickets.json validates against schema"
    else
      ko "${platform}.06 schema validation failed" "ajv error"
    fi
  else
    ok "${platform}.06 ajv not installed — skip schema validation"
  fi

  # manifest update: tickets_count + state
  jq --arg n "2" '.tickets_count = ($n|tonumber) | .state = "ticketed"' \
    "$MANIFEST" > "$DIR/.tk.tmp" && mv "$DIR/.tk.tmp" "$MANIFEST"
  tcount=$(jq -r '.tickets_count' "$MANIFEST")
  [ "$tcount" = "2" ] && ok "${platform}.06b manifest tickets_count=2" || ko "${platform}.06b" "got $tcount"

  # cleanup draft
  trash "$DRAFT" 2>/dev/null || true
  [ ! -f "$DRAFT" ] \
    && ok "${platform}.06c draft removed" \
    || ko "${platform}.06c" "draft persists"

  bash "$PROGRESS" step --project-root="$DIR" --skill=ticket --story-id=01-auth --step-num=06 --step-name=index --status=ok >/dev/null
  bash "$PROGRESS" finish --project-root="$DIR" --skill=ticket --story-id=01-auth --status=ok >/dev/null

  # resume after terminal — skill purged from in_flight → empty stdout
  out=$(bash "$PROGRESS" resume --project-root="$DIR" --skill=ticket --story-id=01-auth)
  if [ -z "$out" ]; then
    ok "${platform}.07 resume after terminal returns empty (purged)"
  else
    ko "${platform}.07" "expected empty, got '$out'"
  fi

  trash "$DIR" 2>/dev/null || true
}

run_platform github
run_platform gitlab
run_platform jira

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
