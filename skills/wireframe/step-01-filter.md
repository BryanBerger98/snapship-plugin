---
step: 01-filter
next_step: 02-design
description: Identify UI tickets via keyword + file-extension heuristic, build the screen list.
---

# step-01 — filter

Decide which tickets need wireframes. Heuristic — surfaced to the user for
override.

## Heuristic

A ticket is "UI" if **any** of:

1. `files[]` contains a path ending in `.tsx`, `.jsx`, `.vue`, `.svelte`,
   `.astro`, `.html`, `.htm`, `.css`, `.scss`, `.module.css`, or paths under
   `components/`, `pages/`, `app/`, `views/`, `screens/`, `routes/`.
2. `title` or `description` matches a UI keyword (case-insensitive):
   `screen|page|view|modal|dialog|form|button|layout|nav|header|footer|sidebar|drawer|toast|empty.state|loading.state|error.state`.
3. `wireframe_screen` already set (from `/ticket` step-04).

## Tasks

1. **Run filter** via the helper (added in this phase):
   ```bash
   ui_tickets=$(bash skills/_shared/filter-ui-tickets.sh \
     --tickets-file=".claude/product/features/${feature_id}/tickets.json")
   ```
   Output: array of `{local_id, title, screen_hint}` where `screen_hint` is the
   first matching keyword/path token (used to seed step-02 screen names).

2. **Build screen list** by aggregating `screen_hint` (or PRD `wireframes` array
   if richer):
   ```json
   [
     {"screen_id": "signup-screen", "states": ["empty", "filled", "error"]},
     {"screen_id": "verify-screen", "states": ["pending", "verified"]}
   ]
   ```

3. **Confirm with user** via `AskUserQuestion` with the screen list:
   - "Proceed with these N screens"
   - "Edit list" (drop screens, rename, add states)

4. **Stash** in `.claude/product/features/${feature_id}/.wireframes-draft.json`:
   ```json
   {
     "ui_tickets": [...],
     "screens": [...]
   }
   ```

5. **Append progress**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="$feature_id" \
     --step-num=01 \
     --step-name=filter \
     --status=ok \
     --skill=wireframe
   ```

## Edge cases

- Zero UI tickets → mark progress `skip` with note `no UI tickets`. Stop the
  pipeline cleanly.
- Mismatch between PRD `wireframes` array and ticket-derived screens → surface
  the diff and ask which list to use.

## Acceptance check

- `screens[]` non-empty (or `skip` exit).
- Each screen has at least one state.

## Next step

→ `step-02-design.md`
