---
step: 03-publish
next_step: 04-finish
description: Push proposed journey content to AFFiNE/Notion via docs-adapter update-page-content. PRD page is never touched.
---

# step-03 — publish

Push the AI-generated journey content. Idempotent: re-running with the same
proposed content is a no-op on the doc platform side (same body → same diff).

## Skip conditions

- `--dry-run` set: log "would update N pages", mark progress `dry-run`, jump to step-04.
- All `proposed-*.md` byte-equal to their corresponding `journey-*.md`: nothing
  changed, mark progress `skip`, jump to step-04.

## Tasks

### A. Per-journey publish

For each `proposed-*.md`:

```bash
for proposed in "$CACHE"/proposed-*.md; do
  base=$(basename "$proposed" .md)              # proposed-auth-login-flow
  key=${base#proposed-}                         # auth-login-flow
  domain=${key%%-*}                             # WARNING: naive — see note below
  jslug=${key#${domain}-}

  page_id=$(echo "$JOURNEYS_RESOLVED" | jq -r --arg d "$domain" --arg s "$jslug" \
    '.[] | select(.domain==$d and .journey_slug==$s) | .page_id')

  if [ -z "$page_id" ] || [ "$page_id" = "null" ]; then
    echo "ERROR: no page_id for ${domain}/${jslug}" >&2
    exit 1
  fi

  # Skip no-op
  current="$CACHE/journey-${domain}-${jslug}.md"
  if [ -f "$current" ] && cmp -s "$current" "$proposed"; then
    echo "skip $key (no change)"
    continue
  fi

  bash skills/_shared/docs-adapter.sh \
    --action=update-page-content \
    --platform="$PLATFORM" \
    --page-id="$page_id" \
    --content-file="$proposed"
  # Maps to MCP — model executes update.
  # Capture success/fail from MCP response.
done
```

> **NOTE on `domain`/`jslug` parsing**: domain slugs may contain hyphens (e.g.
> `user-management`), so `${key%%-*}` is wrong. Use the JSON authority instead:
> iterate `$JOURNEYS_RESOLVED` directly and look up the proposed file by
> `proposed-{domain}-{slug}.md`:
>
> ```bash
> for entry in $(echo "$JOURNEYS_RESOLVED" | jq -c '.[]'); do
>   domain=$(echo "$entry" | jq -r '.domain')
>   jslug=$(echo "$entry" | jq -r '.journey_slug')
>   page_id=$(echo "$entry" | jq -r '.page_id')
>   proposed="$CACHE/proposed-${domain}-${jslug}.md"
>   [ -f "$proposed" ] || { echo "ERROR: missing $proposed" >&2; exit 1; }
>   # ...same publish/skip logic
> done
> ```

### B. PRD page guard

The PRD page MUST NOT be touched. If any future code change accidentally
introduces a write to `$PRD_PAGE_ID`, this step should refuse — assert in code:

```bash
[ "$page_id" = "$PRD_PAGE_ID" ] && {
  echo "FATAL: doc-update attempted to write PRD page — bug." >&2
  exit 99
}
```

### C. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=doc-update \
  --step-num=03 --step-name=publish --status=ok

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=doc-update \
  --story-id="$FEATURE_ID" \
  --step-num=03 \
  --step-name=publish \
  --status=ok
```

## Failure handling

- **MCP error** (auth, rate limit): retry once with backoff. On second failure,
  mark progress `fail` for that journey, continue with remaining ones (partial
  success is acceptable — re-run is idempotent).
- **All journeys fail**: mark progress `fail`, exit 1.

## Acceptance check

- Every journey with changed content has been pushed (or marked skip/fail).
- PRD page (`$PRD_PAGE_ID`) was never written to.

## Next step

→ `step-04-finish.md`
