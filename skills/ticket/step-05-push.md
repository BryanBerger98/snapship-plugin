---
step: 05-push
next_step: 06-index
description: Push drafts to tracker in strict hierarchical order — Epics → User Stories → Tasks/Bugs → milestone → target_version — with idempotence + parent-resolved gating.
---

# step-05 — push

Promote every draft from the ephemeral cache to the tracker. Push order is
**strict** (decision 7b) : children cannot push until their parent's
`platform_id` is resolved. Each step is idempotent by title-lookup.

## Inputs

- `.snap/.runtime/<SUBJECT_ID>/drafts.json` — drafts from step-04 carrying
  `story_type`, `parent_epic_id`, `parent_story_id`, `milestone`,
  `target_version`, `body_rendered`, `commit_type`, `branch_name`.
- `.snap/.runtime/<SUBJECT_ID>/tracker-context.json` — capability snapshot.

## Strict push order (decision 7b)

```
1. Epics nouveaux             (story_type=epic)            → tracker_create_ticket
2. User Stories               (story_type=user-story)      → create + --parent-id Epic if any
3. Tasks/Bugs                 (story_type ∈ {task, bug})   → create + --parent-id Story/Epic if any
4. Milestones                 (all drafts with .milestone)  → set-milestone   (capability-gated)
5. target_version             (non-Epic drafts with .target_version) → set-version (capability-gated)
```

Within each tier, dependency-sort by `depends_on`. **Never** push a child
before its parent has a resolved `platform_id`.

## Idempotence

Every `create` call passes `--idempotency-check=true`. The adapter looks
up by title (scoped to the parent when given) and returns the existing
`platform_id` + `url` if present, skipping the underlying write.

## Blocage child (decision 7b)

If a parent push failed or remains a local draft after its tier (no
`platform_id` written back), **all its children are skipped** with an
explicit UX message :

> « Ticket `<child_local_id>` (`<title>`) bloqué : parent `<parent_local_id>` non poussé. »

Skipped children stay in `drafts.json` with `status: "blocked"` ; resume
via `/snap:ticket --resume` re-tries the parent first.

## Dry-run

If `SNAP_DRY_RUN=true` (from step-00 `--dry-run`), every adapter call
passes `--dry-run`. The adapter logs to telemetry, returns mock IDs, and
the loop still walks the full hierarchy to surface ordering issues
without touching the platform.

## Tasks

### A. Load capabilities

```bash
caps=$(jq '.capabilities' \
  < "$(bash skills/_shared/cache-runtime.sh path "$SUBJECT_ID" \
       tracker-context.json --project-root="$PWD")")
supports_milestone=$(jq -r '.supports_milestone' <<<"$caps")
supports_version=$(jq -r '.supports_version'   <<<"$caps")
```

### B. Tier 1 — Epics

For each `story_type=epic` draft :

```bash
adapter_out=$(bash skills/_shared/tickets-adapter.sh \
  --action=create \
  --project-root="$PWD" \
  --platform="$platform" \
  --story-type=epic \
  --title="$title" \
  --body="$body_rendered" \
  --idempotency-check=true \
  ${SNAP_DRY_RUN:+--dry-run})
rc=$?
```

Branch on `rc` :

- `0` → CLI/dry-run OK ; parse `result.platform_id` + `result.url`.
- `10` → MCP descriptor ; invoke the MCP tool, capture `id` + `url`.
- other → record error, leave `platform_id` unset, continue to next Epic
  (Epic failure does NOT abort the run — its children will be skipped at
  Tier 2/3).

Write `platform_id` + `url` back onto the draft in ephemeral cache.

### C. Tier 2 — User Stories

For each `story_type=user-story` draft, sorted by `depends_on` :

1. **Resolve parent Epic** (if `parent_epic_id` set) :
   - If `parent_epic_id` matches a `local_id` of an Epic draft → look up
     its `platform_id`. If unset → mark child `status=blocked`, emit UX
     message, continue.
   - If `parent_epic_id` already references a tracker Epic (from
     `tracker-context.epics[]`) → use as-is.

2. **Create** with `--parent-id=<resolved>` :
   ```bash
   adapter_out=$(bash skills/_shared/tickets-adapter.sh \
     --action=create \
     --project-root="$PWD" \
     --platform="$platform" \
     --story-type=user-story \
     --title="$title" \
     --body="$body_rendered" \
     --parent-id="$parent_platform_id" \
     --idempotency-check=true \
     ${SNAP_DRY_RUN:+--dry-run})
   ```

3. Cache `platform_id` + `url` back.

### D. Tier 3 — Tasks / Bugs

For each `story_type ∈ {task, bug}` draft, sorted by `depends_on` :

1. **Resolve parent** — `parent_story_id` first, else `parent_epic_id`,
   else standalone (no `--parent-id`). Same gating as Tier 2.
2. **Create** with `--story-type=task|bug` and `--parent-id` when resolved.
3. Cache `platform_id` + `url`.

Note : Bugs in v1.2 are **always flat** per the parent-child matrix (no
parent) — the resolver simply returns no `--parent-id` for bug drafts
even if a `parent_*` field is set (defensive ; step-03b should have
caught this).

### E. Tier 4 — Milestones (capability-gated)

If `supports_milestone=false`, skip the tier entirely with one warn-once
already emitted at step-03c (no repeat here).

Otherwise, for each draft with a non-null `milestone` AND a resolved
`platform_id` :

```bash
bash skills/_shared/tickets-adapter.sh \
  --action=set-milestone \
  --project-root="$PWD" \
  --platform="$platform" \
  --ticket-id="$platform_id" \
  --milestone="$milestone" \
  ${SNAP_DRY_RUN:+--dry-run}
```

### F. Tier 5 — `target_version` (capability-gated)

If `supports_version=false` (GitHub case), skip the tier entirely. The
warn-once is already emitted at step-03c.

Otherwise, for each non-Epic draft with a non-null `target_version` AND a
resolved `platform_id` :

```bash
bash skills/_shared/tickets-adapter.sh \
  --action=set-version \
  --project-root="$PWD" \
  --platform="$platform" \
  --ticket-id="$platform_id" \
  --version-name="$target_version" \
  ${SNAP_DRY_RUN:+--dry-run}
```

### G. GitHub native routing (per ticket, post-create)

Right after each successful create on `platform=github`, invoke
`apply-github-metadata.sh` to route `priority` / `estimated_size` / `scope`
to native Issue Type + Project v2 fields. Residual labels (whatever the
mapping leaves over) are reapplied via `update --labels=…`. Behaviour
unchanged from v1.1 ; skipped when `tickets.github.enabled=false`.

### H. Persist ephemeral state

After every tier completes (or fails for an individual draft), write the
mutated drafts back :

```bash
echo "$drafts_json" | bash skills/_shared/cache-runtime.sh write \
  "$SUBJECT_ID" drafts.json --project-root="$PWD"
```

Ajv-validate before write (same gate as step-04) — `allOf` trivially
holds since `branch_name` / `commit_sha` are unchanged.

### I. Progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=ticket \
  --story-id="$story_id" \
  --step-num=05 \
  --step-name=push \
  --status=ok
```

## Failure handling

- **Auth error** (401/403) : surface the platform message, abort. No retry
  — re-auth is a user task.
- **Validation error** (e.g. JIRA missing required custom field) : record
  field name, mark progress `fail`, stop. User edits config + reruns
  `--resume`.
- **Rate limit** (429) : adapter retries with `Retry-After` (or 60s) once.
  Second 429 fails the tier.
- **Parent failed** : children silently transition to `status=blocked`
  with the UX message above. Resume re-tries parent first.
- **Mid-loop failure** : drafts already pushed keep their `platform_id` in
  the ephemeral cache ; `--resume` skips them on re-entry thanks to the
  idempotency-check.

## Acceptance check

- Every draft is either `status=done` (with `platform_id` + `url`) or
  `status=blocked` (with parent-failed reason).
- No child draft has `platform_id` set without its parent's `platform_id`.
- No Epic draft carries `target_version` after the push (Tier 5 skips
  Epics).
- `supports_milestone=false` → no draft has `milestone` field applied.
- `supports_version=false` → no draft has `target_version` field applied.

## Next step

→ `step-06-index.md`
