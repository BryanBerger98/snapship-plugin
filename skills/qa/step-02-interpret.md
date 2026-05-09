---
step: 02-interpret
next_step: 03-fix
description: Spawn code-reviewer-qa agent with raw evidence; capture severity + qa_feedback_md + flaky verdict.
---

# step-02 — interpret

Hand step-01's raw evidence to the QA reviewer. The agent decides severity,
flaky-vs-real, and authors `qa_feedback_md` for the developer.

## Tasks

### A. Build the prompt

Per ticket, assemble:

```json
{
  "ticket": {full ticket from tickets.json},
  "diff": "git show $sha",
  "regression": {scope, exit_code, log (truncated to 8KB), retry_log if any},
  "wireframe": {screen_id, diff_pct, threshold_pct, png_local, png_ref},
  "acceptance_criteria": [...],
  "config_thresholds": {severity_threshold, qa_cycles_max},
  "current_cycle": 0
}
```

### B. Spawn the agent

Use the `Task` tool with `subagent_type="code-reviewer-qa"` (definition at
`agents/code-reviewer-qa.md`). The reviewer has read-only tools.

```
Task({
  description: "QA review t-001 cycle 0",
  subagent_type: "code-reviewer-qa",
  prompt: <the JSON above + standing instructions from the agent file>
})
```

### C. Parse the response

The agent returns a single JSON fence:

```json
{
  "severity": "none|info|minor|major|critical",
  "flaky_verdict": "real|flaky|inconclusive",
  "qa_feedback_md": "## Findings\n- [major] AC #2 ...\n- [minor] wireframe spacing ...",
  "ac_status": [{"ac_id":"1","status":"pass"}, {"ac_id":"2","status":"fail"}]
}
```

Parse via `skills/_shared/parse-agent-output.sh`. Persist as
`.qa-verdict-${run_id}-${local_id}.json`.

### D. Decision routing

- `severity < threshold` AND `flaky_verdict != real` → step-03 is a no-op,
  jump to step-04 (or step-05 if no retrigger).
- `severity >= threshold` AND `flaky_verdict = real` → step-03.
- `flaky_verdict = inconclusive` → AskUserQuestion: "Reviewer flagged
  inconclusive. Re-run regression? (yes / treat as flaky / treat as real)".

### E. AC status echo

Update `acceptance_criteria` in tickets.json with `checked: true` for `pass`
items (the reviewer's JSON drives the truth — do not mutate text):

```bash
jq --arg lid "$lid" --argjson ac "$ac_status" '
  (.tickets[] | select(.local_id == $lid)).acceptance_criteria as $current
  | (.tickets[] | select(.local_id == $lid)).acceptance_criteria
    |= [
      range(0; ($current | length)) as $i
      | $current[$i] + {checked: ($ac[$i].status == "pass")}
    ]
' "$tickets_file" > "$tickets_file.tmp" && mv "$tickets_file.tmp" "$tickets_file"
```

## Append progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=qa --step-num=02 --step-name=interpret --status=ok \
  --note="severity=$severity flaky=$flaky_verdict"
```

## Acceptance check

- Per-ticket `.qa-verdict-*.json` written with all four fields.
- `acceptance_criteria[].checked` reflects reviewer verdict.

## Next step

→ `step-03-fix.md`
