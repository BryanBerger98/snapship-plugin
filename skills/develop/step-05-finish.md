---
step: 05-finish
description: Surface summary, purge ephemeral subject, hand off to /qa. Terminal step (no next).
---

# step-05 — finish

Wrap up : emit summary, hand off to `/qa`, mandatory ephemeral purge.

v1.2 does **not** mutate any local `.snap/tickets/{story_id}.json` —
the tracker is the single source of truth. Manifest state advance is moved
to `step-99-post-merge.md` and only runs once the PR is merged.

## Tasks

### A. Surface summary

```bash
ticket_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" ticket.json \
              --project-root="$PWD")
commit_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" commit.json \
              --project-root="$PWD")
worktree_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" worktree.json \
                --project-root="$PWD")

platform_id=$(jq -r '.platform_id' <<<"$ticket_json")
title=$(jq -r       '.title'       <<<"$ticket_json")
branch=$(jq -r      '.branch'      <<<"$worktree_json")
sha=$(jq -r         '.commit_sha'  <<<"$commit_json")

cat <<EOF
/develop done — ticket $platform_id:
  - Title: $title
  - Branch: $branch
  - Commit: $sha
  - PR: ${pr_url:-<not pushed>}
  - Status: in_review

Next:
  - /qa --ticket=$platform_id   # validate AC + run regression
EOF
```

If the ticket has a `parent_epic_id`, hint at the auto-close step :

```bash
parent_epic=$(jq -r '.parent_epic_id // ""' <<<"$ticket_json")
if [ -n "$parent_epic" ]; then
  cat <<EOF

Note: parent Epic $parent_epic may be auto-closed post-merge
      (see /develop --post-merge --ticket=$platform_id).
EOF
fi
```

### B. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=develop \
  --step-num=05 --step-name=finish --status=ok \
  --extra='{"ticket":"'"$platform_id"'","commit":"'"$sha"'"}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --step-num=05 \
  --step-name=finish \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --status=ok
```

### C. Mandatory ephemeral purge

```bash
if [ "${KEEP_RUNTIME:-false}" = "true" ]; then
  runtime_path=$(bash skills/_shared/cache-runtime.sh path "$SUBJECT_ID" \
                 --project-root="$PWD")
  echo "DEBUG: ephemeral subject preserved at $runtime_path (--keep-runtime)"
else
  bash skills/_shared/cache-runtime.sh purge "$SUBJECT_ID" \
    --project-root="$PWD"
fi
```

Also clears the EXIT trap registered in step-00.

## Idempotence

Re-running step-05 over an already-finished run rewrites the same fields
(progress already `ok`, runtime already purged — `purge` is no-op).

## Acceptance check

- Summary printed.
- `progress.json.in_flight` no longer contains a `develop` entry for the
  ticket.
- Ephemeral subject directory absent (unless `--keep-runtime`).

## Next step

_None — terminal step. User invokes `/qa` next._
_Post-merge action (Epic auto-close) is in `step-99-post-merge.md`._
