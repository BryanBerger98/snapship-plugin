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

- Existing → update body via `--action=update-pr` (re-rendered from
  `templates/pr-${platform}.md` with current ticket list).
- None → create via `--action=create-pr` with title from feature_title +
  body listing every ticket processed.

### C. Per-ticket platform update

For each ticket that received a commit_sha in this run:

```bash
bash skills/_shared/tickets-adapter.sh \
  --action=update --platform="$platform" --id="$platform_id" \
  --status="in_review" \
  --field="commit_sha=$sha" \
  --project-root="$PWD"
```

MCP descriptor exits 10 → invoke MCP → record success in
`.develop-sync-${run_id}.json`. Best-effort; remote failure does not block the
run (local cache is the working state).

### D. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=develop --status=ok \
  --extra='{"pushed":true,"pr_url":"'"$pr_url"'","tickets_synced":'"$count"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=develop --step-num=04 --step-name=sync --status=ok \
  --note="pr=$pr_url"
```

## Idempotence

- Re-running step-04 with the same SHAs is a no-op (push already in sync; PR
  body re-render writes identical content; ticket update writes idempotent
  status).
- Mid-failure (push ok, PR create failed) → re-run picks up: push is no-op,
  PR step retries.

## Acceptance check

- `git rev-parse "$remote/$branch"` matches local HEAD.
- `pr_url` non-empty (cached in `.develop-sync-${run_id}.json`).
- Every processed ticket has `status=in_review` on platform (best-effort).

## Next step

→ `step-05-finish.md`
