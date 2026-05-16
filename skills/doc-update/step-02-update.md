---
step: 02-update
next_step: 03-publish
description: Per impacted journey, AI patches sections (mode=diff) or rewrites the page (mode=rewrite). Output proposed markdown to cache for review/publish.
---

# step-02 — update

Generate new journey page content. AI step — the model reads each bundle and
emits patched markdown.

## Mode dispatch

```bash
MODE="$AUTO_UPDATE_MODE"  # diff | rewrite
```

- **`diff`** (default): preserve existing content; patch only sections impacted
  by the PRD + diff. Quieter, safer, recommended for stable journeys.
- **`rewrite`**: regenerate the whole journey doc from PRD + git diff + current
  page (used as scaffold). Use for greenfield journeys (empty current page) or
  major refactors.

If a journey's current page is empty (new journey from step-05 publish),
**force `mode=rewrite`** for that journey regardless of config — there is
nothing to diff against.

## Tasks per journey

For each `bundle-*.json` in `$CACHE`:

```bash
for bundle in "$CACHE"/bundle-*.json; do
  domain=$(jq -r '.domain' "$bundle")
  jslug=$(jq -r '.journey_slug' "$bundle")
  journey_current=$(jq -r '.journey_current' "$bundle")
  effective_mode="$MODE"
  [ -z "$(echo "$journey_current" | tr -d '[:space:]')" ] && effective_mode="rewrite"

  out="$CACHE/proposed-${domain}-${jslug}.md"
  # AI step — model executes one of the prompts below, writes result to $out
done
```

### Prompt — mode=diff

```
You are updating a living functional doc page after a feature shipped.

INPUTS:
- Domain: {{domain}}
- Journey: {{journey_slug}}
- Current journey page content (preserve verbatim except where PRD changes affect it):
{{journey_current}}

- PRD page (the change request that just shipped — describes WHAT changed and WHY):
{{prd}}

- Git diff (the actual code change shipped):
{{git_diff}}

TASK:
Patch the current journey doc to reflect the new behavior. Rules:
1. Preserve any section the PRD does NOT impact — verbatim, including formatting.
2. For impacted sections: rewrite them to describe the NEW behavior (post-ship state),
   not the change itself. The journey doc is a living spec, not a changelog.
3. If the PRD adds new behavior with no existing section, add a new section at the
   appropriate location.
4. If the PRD removes behavior, delete the relevant content (do not strike-through).
5. Never reference the PRD, ticket, or git commits. The reader is someone learning
   the product; they don't care about provenance.
6. Keep tone, voice, and section structure consistent with the existing page.

OUTPUT:
The full updated markdown content of the journey page. Nothing else.
```

### Prompt — mode=rewrite

```
You are writing (or rewriting) a living functional doc page after a feature shipped.

INPUTS:
- Domain: {{domain}}
- Journey: {{journey_slug}}
- Current page content (may be empty for a new journey — use as scaffold/style hint):
{{journey_current}}

- PRD page (describes the change):
{{prd}}

- Git diff (actual code shipped):
{{git_diff}}

TASK:
Produce a complete, self-contained journey doc describing the user-facing flow as
it exists now. Rules:
1. Describe the END STATE, not the change. No "we just added X". The reader is
   learning the product.
2. Cover: entry points, happy path, key decision points, error states, exit / next
   steps. Keep concise — link out for deep technical detail.
3. Never reference PRDs, tickets, git history.
4. Use existing page (if non-empty) as a tone/style template; otherwise use clean,
   prose-heavy markdown with H2 sections.

OUTPUT:
The full markdown content of the journey page. Nothing else.
```

## Confirmation (skip in --auto / post-QA hook)

After all journeys patched:

```bash
if [ "$AUTO" != "true" ] && [ "$DRY_RUN" != "true" ]; then
  # Show user a unified diff per journey
  for bundle in "$CACHE"/bundle-*.json; do
    domain=$(jq -r '.domain' "$bundle")
    jslug=$(jq -r '.journey_slug' "$bundle")
    diff -u \
      "$CACHE/journey-${domain}-${jslug}.md" \
      "$CACHE/proposed-${domain}-${jslug}.md" || true
  done

  # AskUserQuestion: Accept / Cancel
  # If Cancel → exit 0, mark progress=skip, leave cache for inspection.
fi
```

## Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=doc-update \
  --step-num=02 --step-name=update --status=ok

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=doc-update \
  --story-id="$FEATURE_ID" \
  --step-num=02 \
  --step-name=update \
  --status=ok
```

## Acceptance check

- One `proposed-*.md` per impacted journey, non-empty.
- For new journeys (current page empty): mode forced to `rewrite`.
- Confirmation shown unless `--auto` or `--dry-run`.

## Next step

→ `step-03-publish.md`
