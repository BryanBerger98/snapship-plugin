---
step: 01-source-resolve
next_step: 02-mockup
description: Build the screen×state list from the targeted ticket(s); detect reusable wireframes or fall back to a tickets-only source.
---

# step-01 — source-resolve

Builds the screen list to mock up from the tickets resolved at step-00
(`target_tickets[]`), the `prd-feature.md` declared screens, and (optionally)
the existing `/wireframe` draft for the same feature.

## Tasks

### 1. Reuse vs. fresh decision

```bash
wf_draft=".snap/wireframes/${story_id}.draft.json"
if [ "$no_wireframe_reuse" = "true" ]; then
  reuse_source="tickets-only"
elif [ -f "$wf_draft" ] && [ "$wireframes_platform" = "$ds_platform" ]; then
  reuse_source="wireframes"
elif [ -f "$wf_draft" ]; then
  reuse_source="wireframes-different-platform"
else
  reuse_source="tickets-only"
fi
```

`AskUserQuestion`:

| `reuse_source`                  | Question                                                                                                  | Options                                                         |
|---------------------------------|-----------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------|
| `wireframes`                    | "Reuse `/wireframe` screens for `/design` mockups?"                                                       | Yes (use same screen list + states) / No (rebuild from tickets) |
| `wireframes-different-platform` | "Wireframes exist on `$wireframes_platform`. Reuse the screen list (assets re-created on `$ds_platform`)?" | Yes (reuse list only) / No (rebuild from tickets)               |
| `tickets-only`                  | (no question — proceed)                                                                                   | —                                                               |

`--no-wireframe-reuse` skips the question and forces `tickets-only`.

### 2. Build screen list

Scope is the `target_tickets[]` resolved at step-00 — **not** the whole
feature. A ticket-id run mocks up only that ticket's screen(s); a story-id
run mocks up every UI ticket of the feature.

- **Reuse mode** → take `screens[]` from
  `.snap/wireframes/${story_id}.draft.json` (or the rendered
  `wireframes-gallery` referenced in `manifest.refs.wireframes_gallery` if
  the draft was trashed post-publish), then
  **intersect** with the screens referenced by `target_tickets[]`. Tag each
  ticket later with `design_mode: "reused"` if it already has a
  `wireframe_screen`.
- **Fresh mode** → run the UI filter on the targeted tickets only:
  ```bash
  ui_tickets=$(bash skills/_shared/filter-ui-tickets.sh \
    --tickets-file=".snap/tickets/${story_id}.json" \
    --only="$target_tickets_csv")
  ```
  Aggregate `screen_hint` into a screen×state list. Default states for
  mockup: `default`, `hover`, `disabled`, `loading`, `error`, `empty`. Trim
  per-screen via `AskUserQuestion` (multi-select).

What each screen should contain is driven by **what the ticket asks for** —
its title, description, and acceptance criteria. Read the ticket body before
composing screens.

### 3. Stash draft

`.snap/designs/${story_id}.draft.json`:

```json
{
  "source": "wireframes|tickets-only",
  "target_tickets": ["t1", "t2"],
  "ui_tickets": [{"local_id":"...","title":"...","screen_hint":"..."}],
  "screens": [
    {"screen_id": "signup-screen", "states": ["default","error"]},
    {"screen_id": "dashboard",     "states": ["default","empty","loading"]}
  ]
}
```

### 4. Edge cases

- Zero UI tickets among the targets → mark progress `skip` with note
  `no UI tickets`. Stop the pipeline cleanly (no mockups, no gallery, no
  link).
- Reuse selected but wireframes file ids mismatch → warn but proceed;
  binding correctness was already validated at step-00.

### 5. Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=design \
  --story-id="$story_id" \
  --step-num=01 \
  --step-name=source-resolve \
  --status=ok
```

## Acceptance check

- `.snap/designs/${story_id}.draft.json` exists with non-empty `screens[]`.
- Each screen has at least one state.

## Next step

→ `step-02-mockup.md`
