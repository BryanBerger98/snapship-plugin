---
step: 03a-standalone
next_step: 04-sync
description: Single-ticket cycle — Phase 1 (analyze/plan/execute/validate) + Phase 2 (3 parallel reviewers + dev fix loop) + atomic commit.
---

# step-03a — develop cycle

Implement one ticket. Two phases, then commit. v1.2 input source is the
ephemeral cache (`ticket.json + parent.json + refs.json` + optional
`digest.json`) — no `.snap/tickets/{story_id}.json` read.

## Phase 1 — Code

Spawn the **snap-developer** agent with the ticket payload :

```bash
ticket_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" ticket.json \
              --project-root="$PWD")
parent_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" parent.json \
              --project-root="$PWD" 2>/dev/null || echo '{}')
refs_json=$(bash   skills/_shared/cache-runtime.sh read "$SUBJECT_ID" refs.json \
              --project-root="$PWD" 2>/dev/null || echo '{}')

# Phase H wire: prefer compact digest when available.
digest_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" digest.json \
              --project-root="$PWD" 2>/dev/null || echo '')

if [ -n "$digest_json" ] && [ "$digest_json" != '{}' ]; then
  payload_kind="ticket_digest"
  payload_json="$digest_json"
else
  payload_kind="ticket_raw"
  payload_json=$(jq -nc \
    --argjson ticket "$ticket_json" \
    --argjson parent "$parent_json" \
    --argjson refs   "$refs_json" \
    '{ticket:$ticket, parent:$parent, refs:$refs}')
fi
```

| Sub-step | What |
|----------|------|
| analyze  | Read `payload_json` + impact_radius + conventions ; identify call sites, tests, types touched. |
| plan     | Produce A/P/C menu (Approach / Parts / Concerns). Surface to user only if `--ask-plan`. |
| execute  | Edit/Write files. Stop at `--max-files` if set. |
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
security) so they execute concurrently. **The orchestrator (this step) spawns
`snap-ticket-digest` once at step-01-fetch (consumer=developer)** ; reviewers
re-use the same condensed payload — subagents do not nest, so the orchestrator
centralises the digest spawn.

Pass the digest under the `{ticket_digest}` input field of every reviewer
prompt (verbatim copy of `digest.json` when available, otherwise the merged
`payload_json` fallback). Each reviewer receives the same brief so their
critiques reference the same source of truth as the developer.

```
{ "severity": "minor|major|critical|none", "feedback_md": "..." }
```

### Severity aggregation

```
overall = max(technical.severity, functional.severity, security.severity)
blocked = any(reviewer.severity >= reviewer.severity_threshold)
```

### Cycle loop

1. `blocked == false` → Phase 2 OK, proceed to commit (also save the rendered
   review-thread payload for step-04 to post on the PR).
2. `blocked == true` and `cycles_used < review_cycles_max` :
   - Build the review context JSON (per-reviewer severity + threshold +
     blocking + findings grouped by file + cross-cutting + suggested fix
     order).
   - Render `aggregated_feedback` via the resolved template :
     ```bash
     agg_tpl=$(bash skills/_shared/resolve-template.sh \
       --kind=aggregated-feedback --project-root="$PWD" | jq -r '.path')
     aggregated_feedback=$(bash skills/_shared/render-template.sh \
       --template="$agg_tpl" --vars="$review_context_json")
     ```
   - Spawn `snap-developer` (write tools enabled) with
     `{payload_json, aggregated_feedback, diff, conventions, repo_root}`.
   - Re-run Phase 2 fresh.
   - `cycles_used += 1`.
3. **Early stop on `critical`** : if any reviewer returned `critical` and
   `auto_apply_review_feedback=false`, halt the cycle and surface to user.
4. Cycles exhausted → branch on `fail_strategy` :
   - `next-ticket` → log severities, status=`blocked`, return (no-op since
     v1.2 is one-ticket-per-call ; flag retained for `/upgrade` migrations).
   - `stop` → dump `aggregated_feedback`, mark progress `fail`.
   - `retry` → re-run Phase 1 once with `retry_strategy_hint=$aggregated_feedback`.
     Then fall through to `--retry-fallback` (default `stop`).

## Commit (atomic)

After Phase 2 OK :

```bash
commit_type=$(jq -r '.commit_type // "feat"' <<<"$ticket_json")
title=$(jq -r '.title' <<<"$ticket_json")
platform_id=$(jq -r '.platform_id' <<<"$ticket_json")
scope=$(jq -r '.scope // ""' <<<"$ticket_json")
scope_suffix=""
[ -n "$scope" ] && scope_suffix="($scope)"

git add -A   # restricted to files Phase 1 touched (skill tracks file set)
git commit -m "$(printf "%s%s: %s (%s)\n" "$commit_type" "$scope_suffix" "$title" "$platform_id")"
sha=$(git rev-parse HEAD)

jq -nc --arg sha "$sha" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{commit_sha:$sha, developed_at:$ts}' \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" commit.json \
      --project-root="$PWD"
```

If a fix-cycle ran after the initial commit, **amend** — one ticket = one commit :

```bash
git add -A && git commit --amend --no-edit
sha=$(git rev-parse HEAD)
jq -nc --arg sha "$sha" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{commit_sha:$sha, developed_at:$ts}' \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" commit.json \
      --project-root="$PWD"
```

## Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --step-num=03a \
  --step-name=develop-cycle \
  --status=ok
```

## Acceptance check

- Phase 1 validate green.
- Phase 2 aggregated severity below thresholds (or `fail_strategy` resolved).
- `commit.json` cached with `commit_sha`.

## Next step

→ `step-04-sync.md`
