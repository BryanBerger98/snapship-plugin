---
step: 01-collect
next_step: 02-update
description: Fetch PRD page content, current journey page contents, and feature-scoped git diff. Cache locally for the AI patch step.
---

# step-01 — collect

Gather all inputs the AI needs to patch journey docs: PRD intent + current journey
state + actual code shipped.

## Tasks

### A. Cache directory

```bash
CACHE=".snap/.doc-update-cache/${FEATURE_ID}"
trash "$CACHE" 2>/dev/null
mkdir -p "$CACHE"
```

Wipe + recreate per run (no cross-run state).

### B. Fetch PRD page content

Read the immutable PRD page once for context:

```bash
bash skills/_shared/docs-adapter.sh \
  --action=lookup-page \
  --platform="$PLATFORM" \
  --page-id="$PRD_PAGE_ID"
```

Maps to MCP — model executes, captures full page content, writes to:

```bash
"$CACHE/prd.md"
```

If the MCP fetch fails (page deleted, auth lapse) — abort with error pointing to
`/snap:define --resume --feature=$FEATURE_ID`.

### C. Fetch current journey pages

For each entry in `$JOURNEYS_RESOLVED`:

```bash
for entry in $(echo "$JOURNEYS_RESOLVED" | jq -c '.[]'); do
  domain=$(echo "$entry" | jq -r '.domain')
  jslug=$(echo "$entry" | jq -r '.journey_slug')
  page_id=$(echo "$entry" | jq -r '.page_id')

  bash skills/_shared/docs-adapter.sh \
    --action=lookup-page \
    --platform="$PLATFORM" \
    --page-id="$page_id"
  # model captures content → "$CACHE/journey-${domain}-${jslug}.md"
done
```

Empty pages (newly-created journeys from step-05 publish) yield empty files —
that's expected. The AI step generates the initial content from PRD + diff.

### D. Compute feature-scoped git diff

The PRD lists tickets; collect their commits. If
`.snap/tickets/${FEATURE_ID}.json` has a `tickets[]` array (populated by
`/snap:ticket` + `/snap:develop`), use those:

```bash
TICKETS_FILE=".snap/tickets/${FEATURE_ID}.json"
TICKETS=$(jq -c '.tickets // []' "$TICKETS_FILE" 2>/dev/null || echo '[]')
if [ "$(echo "$TICKETS" | jq 'length')" -gt 0 ]; then
  # Build commit range from ticket SHAs cached in tickets.json
  # Each ticket has {local_id, commit_sha, ...}
  SHAS=$(echo "$TICKETS" | jq -r '.[] | select(.commit_sha != null) | .commit_sha')
  for sha in $SHAS; do
    git show "$sha" -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.py' '*.go' '*.rs' '*.md' \
      >> "$CACHE/feature.diff"
  done
else
  # Fallback: diff vs main since feature branch creation
  BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master)
  git diff "${BASE}..HEAD" > "$CACHE/feature.diff" 2>/dev/null || true
fi
```

If diff is empty, log a warning but continue — the AI can still patch from PRD
alone (e.g. spec-only changes).

### E. Collect visual assets (wireframes + design)

Surface any visual artifacts attached to this feature so the AI patch
step can cross-reference them in journey docs.

```bash
WF_DIR=".snap/wireframes/${FEATURE_ID}"
DS_DIR=".snap/designs/${FEATURE_ID}"

assets_json="$CACHE/assets.json"
jq -n \
  --argjson wf "$(find "$WF_DIR" -maxdepth 1 -type f \( -name '*.png' -o -name '*.svg' -o -name '*.pdf' \) 2>/dev/null \
                   | jq -R . | jq -s 'map({path:., kind:"wireframe"})')" \
  --argjson ds "$(find "$DS_DIR" -maxdepth 1 -type f \( -name '*.png' -o -name '*.svg' -o -name '*.pdf' \) 2>/dev/null \
                   | jq -R . | jq -s 'map({path:., kind:"design"})')" \
  '{wireframes:($wf // []), design:($ds // [])}' \
  > "$assets_json"
```

Empty arrays are acceptable (feature without UI screens).

### F. Build per-journey context bundle

For each journey, emit a bundle the step-02 AI prompt will read:

```bash
for entry in $(echo "$JOURNEYS_RESOLVED" | jq -c '.[]'); do
  domain=$(echo "$entry" | jq -r '.domain')
  jslug=$(echo "$entry" | jq -r '.journey_slug')
  bundle="$CACHE/bundle-${domain}-${jslug}.json"

  jq -n \
    --arg domain "$domain" \
    --arg slug "$jslug" \
    --arg prd "$(cat "$CACHE/prd.md")" \
    --arg journey "$(cat "$CACHE/journey-${domain}-${jslug}.md" 2>/dev/null || echo '')" \
    --arg diff "$(cat "$CACHE/feature.diff" 2>/dev/null || echo '')" \
    --arg mode "$AUTO_UPDATE_MODE" \
    --argjson assets "$(cat "$CACHE/assets.json" 2>/dev/null || echo '{"wireframes":[],"design":[]}')" \
    '{domain:$domain, journey_slug:$slug, prd:$prd, journey_current:$journey, git_diff:$diff, mode:$mode, assets:$assets}' \
    > "$bundle"
done
```

### G. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=doc-update \
  --step-num=01 --step-name=collect --status=ok

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=doc-update \
  --feature-id="$FEATURE_ID" \
  --step-num=01 \
  --step-name=collect \
  --status=ok
```

## Acceptance check

- `$CACHE/prd.md` exists and non-empty.
- One `journey-*.md` file per impacted journey (may be empty for new journeys).
- One `bundle-*.json` per impacted journey.
- `feature.diff` exists (may be empty — warn but allow).
- `assets.json` exists with `wireframes[]` and `design[]` arrays (empty
  allowed for non-UI features).

## Next step

→ `step-02-update.md`
