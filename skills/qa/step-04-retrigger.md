---
step: 04-retrigger
next_step: 05-finish
description: Opt-in re-run of /develop's 3 reviewers (technical/functional/security) on the post-QA diff. One retrigger max per ticket.
---

# step-04 — retrigger

Optional safety net. If QA cycles altered the diff non-trivially, the original
/develop reviewer verdicts may no longer apply. Re-run them once on the
post-QA diff.

## Skip conditions

- `retrigger=false` (config + no `--retrigger` flag) → no-op.
- Ticket is `blocked` (step-03 exhausted) → no-op.
- `qa_cycles_used == 0` → diff unchanged, no-op.
- Already retriggered this run (`qa_retriggered=true` in ticket) → no-op.

## Tasks

### A. Compute post-QA diff

```bash
tickets_file=".snap/tickets/${feature_id}.json"
sha=$(jq -r --arg lid "$lid" \
  '.tickets[] | select(.local_id == $lid).commit_sha' \
  "$tickets_file")
diff=$(git show "$sha")
```

### B. Spawn 3 reviewers in parallel

**One** message, **three** Agent calls (mirrors /develop step-03a Phase 2):

```
Task({description:"retrigger technical t-001", subagent_type:"snap-code-reviewer-technical", prompt:<diff+ticket>})
Task({description:"retrigger functional t-001", subagent_type:"snap-code-reviewer-functional", prompt:<diff+ticket>})
Task({description:"retrigger security  t-001", subagent_type:"snap-code-reviewer-security",   prompt:<diff+ticket>})
```

Each returns the same JSON fence as /develop:

```json
{ "severity": "none|info|minor|major|critical", "feedback_md": "..." }
```

### C. Aggregate

```
overall = max(technical.severity, functional.severity, security.severity)
```

| Outcome | Action |
|---------|--------|
| `overall < severity_threshold` | Pass — record verdicts, proceed to step-05 |
| `overall >= severity_threshold` | Fail — mark ticket `blocked`, attach all 3 `feedback_md`, proceed to step-05 |

**No fix loop here.** Retrigger is a verification pass, not a second QA cycle.
If it fails, the ticket is blocked and the user decides next move.

### D. Design parity check (opt-in)

Runs when `qa.design_check.enabled=true` AND the ticket carries
`design_url` (or `design_screen` + on-disk asset). Lightweight gate —
asset must exist on disk; richer visual diff is a follow-up.

```bash
dc_enabled=$(jq -r '.qa.design_check.enabled // false' <<<"$CONFIG_JSON")
dc_mode=$(jq -r '.qa.design_check.mode // "asset-presence"' <<<"$CONFIG_JSON")
dc_sev=$(jq -r '.qa.design_check.severity_on_mismatch // "minor"' <<<"$CONFIG_JSON")

if [ "$dc_enabled" = "true" ]; then
  asset=$(jq -r --arg lid "$lid" \
    '.tickets[] | select(.local_id==$lid)
     | (.design_screen // "")' "$tickets_file")
  if [ -n "$asset" ]; then
    design_dir=".snap/designs/${feature_id}"
    case "$dc_mode" in
      asset-presence)
        if ! find "$design_dir" -maxdepth 1 -name "${asset}*" -print -quit 2>/dev/null | grep -q .; then
          # Promote overall severity if asset missing.
          overall=$(printf '%s\n%s\n' "$overall" "$dc_sev" | \
            awk 'BEGIN{r={"none":0,"info":1,"minor":2,"major":3,"critical":4}}
                 {if(!seen)s=$0;else{if(r[$0]>r[s])s=$0}seen=1}END{print s}')
          design_check_fail="asset missing for screen '$asset' in $design_dir"
        fi
        ;;
      playwright)
        # Reserved — visual diff not implemented yet.
        :
        ;;
    esac
  fi
fi
```

If `design_check_fail` set, surface it in the ticket's blocked feedback.

### E. Persist

```bash
tickets_file=".snap/tickets/${feature_id}.json"
tmp=$(mktemp)
jq --arg lid "$lid" --arg sev "$overall" --argjson v "$verdicts_json" \
  '(.tickets[] | select(.local_id == $lid))
     |= (.qa_retriggered = true
         | .qa_retrigger_severity = $sev
         | .qa_retrigger_verdicts = $v)' \
  "$tickets_file" > "$tmp" && mv "$tmp" "$tickets_file"
```

`verdicts_json`:

```json
{
  "technical":  {"severity":"none","feedback_md":"..."},
  "functional": {"severity":"minor","feedback_md":"..."},
  "security":   {"severity":"none","feedback_md":"..."}
}
```

## Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=qa \
  --step-num=04 --step-name=retrigger --status=$status

bash skills/_shared/progress.sh step \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=qa --step-num=04 --step-name=retrigger --status=$status \
  --note="$lid overall=$overall"
```

## Acceptance check

- `qa_retriggered=true` set on the ticket.
- 3 reviewer verdicts persisted (even when severity=none, for audit).
- Ticket either still passes (→ step-05 will mark `qa-validated`) or is now
  `blocked`.

## Next step

→ `step-05-finish.md`
