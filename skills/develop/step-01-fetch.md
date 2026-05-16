---
step: 01-fetch
next_step: 02-prepare
description: Read ticket + parent from ephemeral cache, filter story_type=epic, follow external refs (wireframe/design/doc).
---

# step-01 — fetch

The live ticket and (when relevant) its parent were already pulled into the
ephemeral cache by step-00. This step :

1. asserts they are present,
2. **rejects `story_type=epic`** with a dedicated exit code,
3. extracts external references (wireframe / design / doc URLs) for downstream
   agents.

No PRD lookup, no `.snap/stories/{story_id}/meta.json` read — the ticket is the
single source of truth.

## Tasks

### A. Read from cache

```bash
ticket_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" ticket.json \
              --project-root="$PWD")
parent_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" parent.json \
              --project-root="$PWD" 2>/dev/null || echo '{}')
```

### B. Filter `story_type=epic`

Epic = aggregator, not a deliverable unit. Refuse to develop it.

```bash
story_type=$(jq -r '.story_type // ""' <<<"$ticket_json")
if [ "$story_type" = "epic" ]; then
  cat >&2 <<EOF
ERROR (exit=20): ticket $TICKET_ID has story_type=epic.
Epic n'est pas une unité de livraison — decompose en User Stories
(/snap:ticket --feature=$STORY_ID) puis relance /develop sur une US.
EOF
  exit 20
fi
```

Exit code `20` is reserved for *Epic-refusé* — different from generic `1`
(misuse) and `2` (config error). Wrappers (`/qa`, CI gates) can branch on it.

### C. Validate minimal shape

```bash
title=$(jq -r '.title // ""' <<<"$ticket_json")
ac=$(jq -r '(.acceptance_criteria // []) | length' <<<"$ticket_json")
tech=$(jq -r '.tech_notes // ""' <<<"$ticket_json")

[ -z "$title" ] && { echo "ERROR: ticket has no title" >&2; exit 1; }

if [ "$ac" -eq 0 ] && [ -z "$tech" ]; then
  echo "WARN: ticket has neither acceptance_criteria nor tech_notes."
  # AskUserQuestion in non-auto mode: proceed or cancel.
fi
```

### D. External refs

Extract URLs the ticket points at (wireframe / design / doc page). These are
plain fields on the ticket schema (`wireframe_url`, `design_url`, `doc_url`) ;
some teams also mention them in description / comments via Markdown links —
fall back to a regex sweep when fields are absent.

```bash
refs=$(jq -c '{
  wireframe_url: (.wireframe_url // ""),
  design_url:    (.design_url // ""),
  doc_url:       (.doc_url // "")
}' <<<"$ticket_json")
printf '%s' "$refs" \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" refs.json \
      --project-root="$PWD"
```

Surface a one-liner so the developer agent knows visuals exist before writing
code :

```bash
handoff=$(jq -r '
  [ (if .wireframe_url != "" then "[wireframe] " + .wireframe_url else empty end),
    (if .design_url    != "" then "[design] "    + .design_url    else empty end),
    (if .doc_url       != "" then "[doc] "       + .doc_url       else empty end) ]
  | if length > 0 then "Refs: " + join("; ") else empty end' <<<"$refs")
[ -n "$handoff" ] && echo "$handoff"
```

### E. Plug-in point — `snap-ticket-digest`

Phase H will introduce a `snap-ticket-digest` subagent that distills
`ticket.json + parent.json + refs.json` into a compact developer brief. Until
then, the raw cache files are passed downstream. Plug-in point :

```bash
# Phase H wire (placeholder)
# digest_json=$(bash skills/_shared/spawn-agent.sh snap-ticket-digest \
#   --ticket="$SUBJECT_ID/ticket.json" \
#   --parent="$SUBJECT_ID/parent.json" \
#   --refs="$SUBJECT_ID/refs.json")
# printf '%s' "$digest_json" \
#   | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" digest.json
```

### F. Sync ticket status (idempotent)

Mark the ticket as `in_progress` on the tracker (best-effort) :

```bash
platform_id=$(jq -r '.platform_id' <<<"$ticket_json")
bash skills/_shared/tickets-adapter.sh \
  --action=update --platform="$PLATFORM" --ticket-id="$platform_id" \
  --state=in_progress --project-root="$PWD" \
  >/dev/null 2>&1 || true
```

Remote failure is non-fatal — local cache drives behaviour.

### G. Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --step-num=01 \
  --step-name=fetch \
  --status=ok
```

## Acceptance check

- `ticket.json` readable from cache.
- `story_type` ∈ `{user-story, task, bug}` ; Epic rejected with exit 20.
- `refs.json` written (URLs may be empty strings — that's fine).

## Next step

→ `step-02-prepare.md`
