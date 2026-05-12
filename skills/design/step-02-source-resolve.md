---
step: 02-source-resolve
next_step: 03-mockup
description: Mode mockup — detect existing wireframes binding or fall back to tickets-only source. Builds the screen×state list.
---

# step-02 — source-resolve

Runs only when `mode == mockup`. Builds the screen list to mock up by
combining `prd-feature.md` declared screens, `tickets.json` UI filter, and
(optionally) the existing `/wireframe` draft for the same feature.

## Tasks

### 1. Reuse vs. fresh decision

```bash
wf_draft=".claude/product/features/${feature_id}/.wireframes-draft.json"
if [ -f "$wf_draft" ] && [ "$wireframes_platform" = "$ds_platform" ]; then
  reuse_source="wireframes"
elif [ -f "$wf_draft" ]; then
  reuse_source="wireframes-different-platform"
else
  reuse_source="tickets-only"
fi
```

`AskUserQuestion`:

| `reuse_source`                       | Question                                                                                          | Options                                                              |
|--------------------------------------|---------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `wireframes`                         | "Reuse `/wireframe` screens for `/design` mockups?"                                               | Yes (use same screen list + states) / No (rebuild from tickets)      |
| `wireframes-different-platform`      | "Wireframes exist on `$wireframes_platform`. Reuse the screen list (assets re-created on `$ds_platform`)?" | Yes (reuse list only) / No (rebuild from tickets)                    |
| `tickets-only`                       | (no question — proceed)                                                                            | —                                                                    |

### 2. Build screen list

- **Reuse mode** → copy `screens[]` from `.wireframes-draft.json`. Tag each
  ticket later with `design_mode: "reused"` if the ticket already has a
  `wireframe_screen`.
- **Fresh mode** → run the same UI filter as `/wireframe step-01`:
  ```bash
  ui_tickets=$(bash skills/_shared/filter-ui-tickets.sh \
    --tickets-file=".claude/product/features/${feature_id}/tickets.json")
  ```
  Aggregate `screen_hint` into a screen×state list. Default states for
  mockup: `default`, `hover`, `disabled`, `loading`, `error`, `empty`. Trim
  per-screen via `AskUserQuestion` (multi-select).

### 3. Stash draft

`.claude/product/features/${feature_id}/.design-draft.json`:

```json
{
  "source": "wireframes|tickets-only",
  "ui_tickets": [{"local_id":"...","title":"...","screen_hint":"..."}],
  "screens": [
    {"screen_id": "signup-screen", "states": ["default","error"]},
    {"screen_id": "dashboard",     "states": ["default","empty","loading"]}
  ]
}
```

### 4. Edge cases

- Zero UI tickets → mark progress `skip` with note `no UI tickets`. Stop
  the pipeline cleanly (no mockups produced, no gallery, no link).
- Reuse selected but wireframes file ids mismatch → warn but proceed;
  binding correctness was already validated at step-00.

### 5. Append progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id="$feature_id" \
  --step-num=02 \
  --step-name=source-resolve \
  --status=ok \
  --skill=design \
  --extra="{\"source\":\"$source\"}"
```

## Acceptance check

- `.design-draft.json` exists with non-empty `screens[]`.
- Each screen has at least one state.

## Next step

→ `step-03-mockup.md`
