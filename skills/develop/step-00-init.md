---
step: 00-init
next_step: 01-fetch
description: Parse args, resolve target (ticket-id or feature_id), load config, pre-flight git + reviewers.
---

# step-00 — init

Bootstrap a `/develop` run. The target may be a single ticket (standalone) or a
feature (session loop).

## Tasks

1. **Parse args**: `--resume`/`-r`, positional `<id>`,
   `--dry-run`, `--allow-dirty`, `--retry-fallback=next-ticket|stop`.

2. **Resume short-circuit**:

   ```bash
   resume_line=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" \
     --skill=develop \
     --feature-id="${feature_id:-_global}")
   ```

   Same rc=0/1/2 contract as the other skills.

3. **Resolve target**. Three paths from positional `<id>`:
   - **Empty** → AskUserQuestion: "Which ticket / feature?" enumerating tickets
     with `status in (todo, in_progress)`.
   - **Ticket-shaped** (regex: `^[A-Z]+-[0-9]+$|^#[0-9]+$|^t-[0-9]+$`) → standalone
     mode. Cross-reference `.snap/tickets/*.json` files to locate the parent
     feature_id.
   - **Feature-shaped** (`^[0-9]{2}-[a-z0-9-]+$`) → session loop.

4. **Require config + load**:

   ```bash
   [ -f "$PWD/snap.config.json" ] || {
     echo "ERROR: snap.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   review_cycles_max=$(jq '.develop.review_cycles_max // 3' <<<"$CONFIG_JSON")
   fail_strategy=$(jq -r '.develop.fail_strategy // "next-ticket"' <<<"$CONFIG_JSON")
   ```

5. **Pre-flight**:
   - `git rev-parse --is-inside-work-tree` — abort if not in a repo.
   - Working tree clean (unless `--allow-dirty`):

     ```bash
     [ -z "$(git status --porcelain)" ] || { echo "ERROR: dirty tree"; exit 1; }
     ```

   - Branch protection: refuse to commit directly on
     `repository.protected_branches`. Branch will be created in step-02.
   - Reviewers reachable: `agents/snap-code-reviewer-{technical,functional,security}.md`
     and `agents/snap-developer.md` exist (verified once via the `Task` tool dispatch
     in step-03a; here we only confirm the files are present).

6. **Design handoff hint**. After feature is resolved, scan
   `.snap/tickets/${feature_id}.json` for any ticket carrying `design_url`
   (or `wireframe_url`). If at least one is present, surface a one-liner:

   ```bash
   tickets_file=".snap/tickets/${feature_id}.json"
   handoff=$(jq -r '
     [.tickets[] | select((.design_url // "") != "" or (.wireframe_url // "") != "")
                 | {id:(.platform_id // .local_id),
                    title,
                    url:(.design_url // .wireframe_url),
                    kind:(if .design_url != null and .design_url != "" then "design" else "wireframe" end)}]
     | if length > 0 then
         "Design handoff: " + (map("[\(.kind)] \(.id) \(.title) → \(.url)") | join("; "))
       else empty end
   ' "$tickets_file" 2>/dev/null || true)
   [ -n "$handoff" ] && echo "$handoff"
   ```

   No behaviour change — pure informational surface so the developer
   agent knows visuals exist before writing code.

7. **Append progress**:

   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=develop \
     --feature-id="$feature_id" \
     --step-num=00 \
     --step-name=init \
     --status=ok
   ```

## Acceptance check

- `target_kind` set to `ticket | feature`.
- `feature_id` resolved (always — even in standalone mode, parent feature is
  known).
- Config loaded; `review_cycles_max` and `fail_strategy` materialised.

## Next step

→ `step-01-fetch.md`
