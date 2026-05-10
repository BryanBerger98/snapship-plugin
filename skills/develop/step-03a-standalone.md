---
step: 03a-standalone
next_step: 04-sync
description: Single-ticket cycle — Phase 1 (analyze/plan/execute/validate) + Phase 2 (3 parallel reviewers + dev fix loop) + atomic commit.
---

# step-03a — standalone

Implement one ticket. Two phases, then commit.

## Phase 1 — Code

Spawn the **developer** agent (`agents/developer.md`) with a structured prompt:

| Sub-step | What |
|----------|------|
| analyze | Read ticket + impact_radius + conventions; identify call sites, tests, types touched. |
| plan | Produce A/P/C menu (Approach / Parts / Concerns). Surface to user only if `--ask-plan`. |
| execute | Edit/Write files. Stop at `--max-files` if set. |
| validate | Run `lint_command`, `typecheck_command`, scoped `test_command` (only files touched). |

Phase 1 retries up to 3 times if `validate` fails (fix loop internal to the
agent). Hard error after 3 → emit progress `fail`, surface diff, stop.

### Output of Phase 1

```json
{
  "phase": 1,
  "files_changed": ["src/auth/signup.ts", ...],
  "diff_summary": "...",
  "validate": {"lint": "ok", "typecheck": "ok", "test": "ok"}
}
```

## Phase 2 — Reviews (parallel, 1 message N Agent calls)

Issue **one** message containing **three** Agent calls (technical, functional,
security) so they execute concurrently. The skill then aggregates the JSON
fences each reviewer returns:

```
{ "severity": "minor|major|critical|none", "feedback_md": "..." }
```

### Severity aggregation

```
overall = max(technical.severity, functional.severity, security.severity)
```

Comparison against thresholds (per-reviewer):

```
blocked = any(reviewer.severity >= reviewer.severity_threshold)
```

### Cycle loop

1. If `blocked == false` → Phase 2 OK, proceed to commit (also save the rendered
   review-thread payload for step-04 to post on the PR).
2. If `blocked == true` and cycles_used < `review_cycles_max`:
   - Build the review context JSON (per-reviewer severity + threshold +
     blocking + findings grouped by file + cross-cutting + suggested fix
     order) from the three reviewer outputs.
   - Render `aggregated_feedback` via the resolved template (user override >
     bundled `aggregated-feedback.md`):
     ```bash
     agg_tpl=$(bash skills/_shared/resolve-template.sh \
       --kind=aggregated-feedback --project-root="$PWD")
     aggregated_feedback=$(bash skills/_shared/render-template.sh \
       --template="$agg_tpl" --vars="$review_context_json")
     ```
   - Spawn `developer` agent (write tools enabled) with
     `{aggregated_feedback, diff, ticket, conventions, repo_root}`.
   - Re-run Phase 2 (3 reviewers parallel, fresh).
   - cycles_used += 1.
3. **Early stop on `critical`**: if any reviewer returned `critical` and
   `auto_apply_review_feedback=false`, halt the cycle immediately and surface to
   user.
4. Cycles exhausted → branch on `fail_strategy`:
   - `next-ticket` (loop modes only) → log severities, status=`blocked`, return.
   - `stop` → dump `aggregated_feedback`, mark progress `fail`.
   - `retry` → re-run Phase 1 once with `retry_strategy_hint="Re-architect; the
     feedback so far is\n\n$aggregated_feedback"`. After retry → fall through to
     `--retry-fallback` (default `stop`).

## Commit (atomic)

After Phase 2 OK:

```bash
type=$(jq -r '.type // "feat"' <<<"$ticket_json")
scope=$(jq -r '.feature_id' <<<"$ticket_json" | sed 's/^[0-9]*-//')
title=$(jq -r '.title' <<<"$ticket_json")
local_id=$(jq -r '.local_id' <<<"$ticket_json")

git add -A   # restricted to files Phase 1 touched (skill tracks file set)
git commit -m "$(printf "%s(%s): %s (%s)\n" "$type" "$scope" "$title" "$local_id")"
sha=$(git rev-parse HEAD)

jq --arg lid "$local_id" --arg sha "$sha" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '(.tickets[] | select(.local_id == $lid))
     |= (.commit_sha = $sha | .developed_at = $now | .status = "in_review")' \
  "$tickets_file" > "$tickets_file.tmp" && mv "$tickets_file.tmp" "$tickets_file"
```

If a fix-cycle ran after the initial commit, **amend** instead of creating new
commits — one ticket = one commit:

```bash
git add -A && git commit --amend --no-edit
```

## Append progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=develop --step-num=03a --step-name=standalone --status=ok \
  --note="$local_id sha=$sha cycles=$cycles_used"
```

## Acceptance check

- Phase 1 validate green.
- Phase 2 aggregated severity below thresholds (or fail_strategy resolved).
- `commit_sha` set in tickets.json.

## Next step

→ `step-04-sync.md`
