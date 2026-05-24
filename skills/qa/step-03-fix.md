---
step: 03-fix
next_step: 04-retrigger
description: Dev↔QA cycle — developer agent applies qa_feedback_md → amend commit → re-run step-01. Bounded by qa_cycles_max.
---

# step-03 — fix

Close the loop on real findings. The developer agent applies `qa_feedback_md`,
amends the ticket commit, then we re-collect (step-01) and re-interpret
(step-02) until severity drops below threshold or `qa_cycles_max` is hit.

## Skip conditions

- `severity < severity_threshold` AND `flaky_verdict != real` → step is a no-op.
- `--dry-run` → log findings, do not amend.

## Confirmation gate (`auto_apply_qa_feedback`)

Mirrors `/develop`'s `auto_apply_review_feedback` (step-03a-standalone). Resolve
the flag once (embedded defaults guarantee the key; the `//` fallback is
belt-and-suspenders so a missing/partial config never breaks the cycle):

```bash
CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
auto_apply=$(jq -r '.qa.auto_apply_qa_feedback // true' <<<"$CONFIG_JSON")
```

Before spawning the developer agent (task A below) for **each** fix cycle:

- `auto_apply == true` (default) → apply the QA feedback **without asking**.
- `auto_apply == false` → ask the user first, via `ask-or-default.sh` (auto-mode
  mirrors the read flag, so `false` always prompts; default answer `apply`):

  ```bash
  ans=$(bash skills/_shared/ask-or-default.sh \
    --auto-mode="$auto_apply" \
    --question-id=apply-qa-feedback \
    --question="Appliquer les retours QA (cycle $((cycles_used + 1))) ?" \
    --options=apply,skip \
    --default=apply \
    --header="Revue QA")
  # auto_apply=false → $ans is a JSON {action:"ask",...} : surface it through
  #   AskUserQuestion, then read the user's choice.
  # auto_apply=true  → $ans is "apply" (raw) : proceed silently.
  ```

  If the user picks `skip`, do **not** spawn the developer: surface
  `qa_feedback_md` to the user, mark the ticket `blocked`, and jump to step-05.

## Tasks

### A. Spawn developer agent (write-enabled)

Reuse `agents/snap-developer.md`. Prompt assembly:

```json
{
  "ticket": {full ticket},
  "qa_feedback_md": "<from step-02>",
  "diff": "git show ${commit_sha}",
  "conventions": <from conventions cache>,
  "repo_root": "$PWD",
  "instructions": "Apply qa_feedback. Do not introduce new scope. Re-run lint/typecheck/test."
}
```

```
Task({
  description: "QA fix t-001 cycle 1",
  subagent_type: "snap-developer",
  prompt: <prompt>
})
```

The agent edits files, runs `format_command` + `lint_command` +
`typecheck_command` + scoped `test_command` itself (skipping any unset), retries
up to 3x internally (mirrors /develop Phase 1).

### B. Amend the ticket commit

One ticket = one commit (matches /develop step-03a):

```bash
git add -A
git commit --amend --no-edit
new_sha=$(git rev-parse HEAD)

tickets_file=".snap/tickets/${story_id}.json"
tmp=$(mktemp)
jq --arg lid "$lid" --arg sha "$new_sha" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '(.tickets[] | select(.local_id == $lid))
     |= (.commit_sha = $sha | .updated_at = $now)' \
  "$tickets_file" > "$tmp" && mv "$tmp" "$tickets_file"
```

If the working tree is dirty after amend (agent left untracked junk), abort
the cycle and surface the state to the user — never silently lose changes.

### C. Re-collect + re-interpret

Loop back through step-01 + step-02 with `current_cycle += 1`:

```bash
cycles_used=$(( cycles_used + 1 ))
bash skills/qa/_invoke-step.sh 01-collect    # convention: each step file is invokable
bash skills/qa/_invoke-step.sh 02-interpret
```

(In practice the runtime walks `next_step` frontmatter; the loop here is
expressed as "go back to step-01 with cycle++".)

### D. Termination

| Condition | Action |
|-----------|--------|
| New severity < threshold AND flaky_verdict ≠ real | Exit cycle → step-04 |
| `cycles_used >= qa_cycles_max` | Mark ticket `blocked`, store last `qa_feedback_md` in ticket, jump to step-05 |
| Developer agent failed all 3 internal retries | Mark ticket `blocked`, surface diff, jump to step-05 |
| `flaky_verdict = flaky` after retry | Treat as pass — exit cycle without amend |

### E. Persist cycle state

```bash
tmp=$(mktemp)
jq --arg lid "$lid" --argjson c "$cycles_used" \
   --arg sev "$severity" --arg verdict "$flaky_verdict" \
  '(.tickets[] | select(.local_id == $lid))
     |= (.qa_cycles_used = $c
         | .qa_last_severity = $sev
         | .qa_last_flaky_verdict = $verdict)' \
  "$tickets_file" > "$tmp" && mv "$tmp" "$tickets_file"
```

## Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=qa \
  --step-num=03 --step-name=fix --status=$status

bash skills/_shared/progress.sh step \
  --project-root="$PWD" --story-id="$story_id" \
  --skill=qa --step-num=03 --step-name=fix --status=$status \
  --note="$lid cycles=$cycles_used sev=$severity"
```

`status=ok` when cycle resolved, `fail` when blocked / exhausted.

## Acceptance check

- Either: ticket commit amended + new severity < threshold,
  or: ticket flagged `blocked` with last verdict persisted.
- `qa_cycles_used` reflects actual loop count.
- No uncommitted changes in working tree.

## Next step

→ `step-04-retrigger.md`
