---
step: 04-sync
next_step: 05-finish
description: Push the branch, open or update the PR, patch each processed ticket on the platform.
---

# step-04 — sync

Land local commits on the remote and reflect status on the ticket platform.

## Tasks

### A. Push (idempotent)

```bash
remote=$(git remote | head -n1)
[ -n "$remote" ] || { echo "ERROR: no git remote"; exit 1; }

git push --set-upstream "$remote" "$branch"
```

Failure modes:
- `non-fast-forward` → fetch, surface to user (`git pull --rebase` or abort).
- `permission denied` → propagate verbatim.

### B. PR (idempotent)

Detect existing PR for this branch:

```bash
existing_pr=$(bash skills/_shared/tickets-adapter.sh \
  --action=list-prs --platform="$platform" \
  --branch="$branch" --project-root="$PWD")
```

Resolve the PR template (config override > repo-native > bundled, per platform):

```bash
pr_tpl_json=$(bash skills/_shared/resolve-template.sh \
  --kind=pr --platform="$platform" --project-root="$PWD")
pr_tpl=$(printf '%s' "$pr_tpl_json" | jq -r '.path')
pr_render_mode=$(printf '%s' "$pr_tpl_json" | jq -r '.render_mode')
```

Branch on `pr_render_mode`:

- **`mustache`** (config override or bundled) → render with `render-template.sh`:
  ```bash
  pr_body=$(bash skills/_shared/render-template.sh \
    --template="$pr_tpl" --context=".snap/queues/${story_id}.pr-context.json")
  ```
- **`scaffold`** (repo-native `.github/.gitlab` PULL_REQUEST_TEMPLATE): the file
  is a static markdown scaffold. Read `$pr_tpl`, **strip any YAML frontmatter**,
  then fill each section in place from
  `.snap/queues/${story_id}.pr-context.json` (tickets processed, review
  verdict, test summary). Keep the repo's heading order and checklists; drop
  placeholder prose. The result is `pr_body`.

- Existing → update body via `--action=update-pr` with the rendered body.
- None → create via `--action=create-pr` with title from feature_title +
  rendered body listing every ticket processed.

### C. Post review thread (best-effort)

After PR exists, post the structured review thread as a comment so humans can
read the review verdict inline. The review thread is an internal snap artifact
— there is no `.github`/`.gitlab` convention for it — so it always resolves to
the config override or bundled `review-thread/${platform}.md` (`render_mode`
is always `mustache`):

```bash
review_tpl=$(bash skills/_shared/resolve-template.sh \
  --kind=review-thread --platform="$platform" --project-root="$PWD" \
  | jq -r '.path')
review_body=$(bash skills/_shared/render-template.sh \
  --template="$review_tpl" --context=".snap/queues/${story_id}.review-context.json")

bash skills/_shared/tickets-adapter.sh \
  --action=comment-pr --platform="$platform" \
  --pr-id="$pr_id" --body-file=<(printf '%s' "$review_body") \
  --project-root="$PWD" || echo "WARN: review thread post failed (best-effort)" >&2
```

Failure modes (best-effort — never block the run):
- `comment-pr` adapter exits non-zero → log warning, continue.
- JIRA platform → adapter posts on the parent ticket instead of a PR (no PR
  concept on JIRA; see `tickets-adapter.sh` semantics).

### D. Per-ticket platform update

For each ticket that received a commit_sha in this run:

```bash
bash skills/_shared/tickets-adapter.sh \
  --action=update --platform="$platform" --id="$platform_id" \
  --status="in_review" \
  --field="commit_sha=$sha" \
  --project-root="$PWD"
```

MCP descriptor exits 10 → invoke MCP → record success in
`.snap/queues/${story_id}.sync.json`. Best-effort; remote failure does not
block the run (local cache is the working state).

### E. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=develop \
  --step-num=04 --step-name=sync --status=ok \
  --extra='{"pushed":true,"pr_url":"'"$pr_url"'","tickets_synced":'"$count"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$story_id" \
  --step-num=04 \
  --step-name=sync \
  --status=ok
```

## Idempotence

- Re-running step-04 with the same SHAs is a no-op (push already in sync; PR
  body re-render writes identical content; ticket update writes idempotent
  status).
- Mid-failure (push ok, PR create failed) → re-run picks up: push is no-op,
  PR step retries.

## Acceptance check

- `git rev-parse "$remote/$branch"` matches local HEAD.
- `pr_url` non-empty (cached in `.snap/queues/${story_id}.sync.json`).
- Every processed ticket has `status=in_review` on platform (best-effort).

## Next step

→ `step-05-finish.md`
