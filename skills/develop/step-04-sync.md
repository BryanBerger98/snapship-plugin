---
step: 04-sync
next_step: 05-finish
description: Push the branch, open or update the PR, patch the ticket status remote.
---

# step-04 — sync

Land local commits on the remote and reflect status on the tracker.

## Tasks

### A. Push (idempotent)

```bash
worktree_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" worktree.json \
                --project-root="$PWD")
branch=$(jq -r '.branch' <<<"$worktree_json")

remote=$(git remote | head -n1)
[ -n "$remote" ] || { echo "ERROR: no git remote"; exit 1; }

git push --set-upstream "$remote" "$branch"
```

Failure modes :
- `non-fast-forward` → fetch, surface to user (`git pull --rebase` or abort).
- `permission denied` → propagate verbatim.

### B. PR (idempotent)

Detect existing PR for this branch :

```bash
existing_pr=$(bash skills/_shared/tickets-adapter.sh \
  --action=list-prs --platform="$PLATFORM" \
  --branch="$branch" --project-root="$PWD")
```

Resolve PR template (config override > repo-native > bundled) :

```bash
pr_tpl_json=$(bash skills/_shared/resolve-template.sh \
  --kind=pr --platform="$PLATFORM" --project-root="$PWD")
pr_tpl=$(printf '%s' "$pr_tpl_json" | jq -r '.path')
pr_render_mode=$(printf '%s' "$pr_tpl_json" | jq -r '.render_mode')
```

Build PR context — one ticket only :

```bash
ticket_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" ticket.json \
              --project-root="$PWD")
commit_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" commit.json \
              --project-root="$PWD")

pr_ctx=$(jq -nc \
  --argjson t "$ticket_json" \
  --argjson c "$commit_json" \
  '{ticket:$t, commit:$c}')
printf '%s' "$pr_ctx" \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" pr-context.json \
      --project-root="$PWD"
```

Render and push :

- **`mustache`** → `render-template.sh --template="$pr_tpl" --context=<pr-context.json>`.
- **`scaffold`** → read repo-native template, strip frontmatter, fill from
  `pr-context.json`.

- Existing PR → `--action=update-pr` with rendered body.
- None → `--action=create-pr` with title = `${commit_type}: ${title} (${platform_id})`.

### C. Post review thread (best-effort)

```bash
review_tpl=$(bash skills/_shared/resolve-template.sh \
  --kind=review-thread --platform="$PLATFORM" --project-root="$PWD" \
  | jq -r '.path')
review_body=$(bash skills/_shared/render-template.sh \
  --template="$review_tpl" \
  --context="$(bash skills/_shared/cache-runtime.sh path "$SUBJECT_ID" review-context.json --project-root="$PWD")")

bash skills/_shared/tickets-adapter.sh \
  --action=comment-pr --platform="$PLATFORM" \
  --pr-id="$pr_id" --body-file=<(printf '%s' "$review_body") \
  --project-root="$PWD" || echo "WARN: review thread post failed (best-effort)" >&2
```

Best-effort — adapter failure never blocks the run.

### D. Patch ticket status remote

```bash
platform_id=$(jq -r '.platform_id' <<<"$ticket_json")
commit_sha=$(jq -r '.commit_sha' <<<"$commit_json")

bash skills/_shared/tickets-adapter.sh \
  --action=update --platform="$PLATFORM" --ticket-id="$platform_id" \
  --state=in_review \
  --project-root="$PWD" \
  || echo "WARN: ticket status update failed (best-effort)" >&2

# Comment the commit SHA back on the ticket so the trail is preserved remote-side.
bash skills/_shared/tickets-adapter.sh \
  --action=comment --platform="$PLATFORM" --ticket-id="$platform_id" \
  --comment="Implemented in $commit_sha — see PR $pr_url" \
  --project-root="$PWD" \
  >/dev/null 2>&1 || true
```

### E. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=develop \
  --step-num=04 --step-name=sync --status=ok \
  --extra='{"pushed":true,"pr_url":"'"$pr_url"'","ticket":"'"$platform_id"'"}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --step-num=04 \
  --step-name=sync \
  --status=ok
```

## Idempotence

- Re-running step-04 with the same SHA is a no-op (push in sync ; PR body
  re-render identical ; ticket update idempotent).
- Mid-failure (push ok, PR create failed) → re-run picks up : push no-op, PR
  step retries.

## Acceptance check

- `git rev-parse "$remote/$branch"` matches local HEAD.
- `pr_url` non-empty (cached in `pr-result.json`).
- Ticket status `in_review` on platform (best-effort).

## Next step

→ `step-05-finish.md`
