---
step: 05-finish
description: Terminal — set ticket status (qa-validated | blocked), update platform body with QA verdict, telemetry, summary.
---

# step-05 — finish

Wrap the QA run. Ticket reaches `qa-validated` or stays `blocked` with full
context attached.

This step has no `next_step` — it is terminal.

## Tasks

### A. Resolve final status per ticket

```bash
final_sev=${qa_retrigger_severity:-$qa_last_severity}
flaky=$qa_last_flaky_verdict
blocked=$qa_blocked   # set true by step-03/04 on exhaustion or retrigger fail

if [ "$blocked" = "true" ]; then
  new_status="blocked"
elif [ "$(severity_rank "$final_sev")" -lt "$(severity_rank "$sev_thr")" ] \
     && [ "$flaky" != "real" ]; then
  new_status="qa-validated"
else
  new_status="blocked"
fi
```

### B. Update tickets.json

```bash
jq --arg lid "$lid" --arg s "$new_status" \
   --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  (.tickets[] | select(.local_id == $lid))
    |= (.status = $s
        | .qa_validated_at = (if $s == "qa-validated" then $now else null end))
' "$tickets_file" > "$tickets_file.tmp" && mv "$tickets_file.tmp" "$tickets_file"
```

### C. Amend ticket platform body

Per-platform template (github/linear/jira) — append a QA verdict block:

```bash
bash skills/_shared/render-template.sh \
  --tpl=skills/_shared/templates/qa-verdict-${platform}.md.tpl \
  --json="$ctx_json" > /tmp/qa-verdict.md

bash skills/_shared/tickets-adapter.sh update-body \
  --platform="$platform" --ticket-id="$ticket_id" \
  --append-file=/tmp/qa-verdict.md
```

`ctx_json` carries: `severity`, `flaky_verdict`, `qa_cycles_used`,
`qa_retriggered`, `qa_feedback_md` (last cycle), AC checklist, regression
exit code, wireframe diff %.

Adapter `update-body` is a no-op for missing platforms (CLI-direct degraded
mode logs warning but does not fail the run — the local `tickets.json` is
authoritative).

### D. Cleanup transient files

```bash
trash .qa-collect-*.json 2>/dev/null || true
trash .qa-verdict-*.json 2>/dev/null || true
trash .tmp/regression-*.log 2>/dev/null || true
```

### E. Update feature index

```bash
bash skills/_shared/update-index.sh --project-root="$PWD"
```

### F. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=qa --status=ok \
  --extra='{"validated":'"$validated_count"',"blocked":'"$blocked_count"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=qa --step-num=05 --step-name=finish --status=ok \
  --note="validated=$validated_count blocked=$blocked_count"
```

### G. Summary to stdout

```
/qa done — feature ${feature_id}:
  - Validated: t-001, t-002 (2)
  - Blocked:   t-003 (severity=major)
  - Cycles:    avg 1.3 / max 2

Next:
  - Blocked tickets need manual triage or `/develop --resume` then `/qa <id>`.
  - All validated → ready to merge / release.
```

## Idempotence

Re-running step-05 over an already-finished ticket rewrites the same status
+ timestamp (no churn). `update-body --append-file` checks for an existing
verdict block keyed by run_id and replaces in place.

## Acceptance check

- Each targeted ticket: `status` is `qa-validated` or `blocked`.
- `qa_validated_at` set on validated tickets, null on blocked.
- Platform body updated (or warning logged on adapter failure).
- `progress.md` ends with `qa step-05 finish — ok`.

## Next step

_None — terminal step._
