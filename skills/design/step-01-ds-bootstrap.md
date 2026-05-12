---
step: 01-ds-bootstrap
next_step: end (ds-init|ds-update) | 02-source-resolve (mockup chained)
description: Bootstrap or patch the design system file. Compiles YAML specs via Bridge (figma) or applies components via penpot-helper (penpot).
---

# step-01 — ds-bootstrap

Run **only** when `mode ∈ {ds-init, ds-update}`. Mockup mode skips directly
to step-02.

## Inputs

- `$ds_platform` (`penpot|figma`) from state.
- `$ds_file_id` / `$ds_file_key` from state.
- `$mode` (`ds-init|ds-update`) from state.
- Spec source: first existing of
  - `design-system/specs/*.yaml` (user override),
  - `skills/_shared/templates/design-system-defaults/*.yaml` (bundled defaults).

## Tasks

### 1. Locate specs

```bash
spec_dir="design-system/specs"
[ -d "$spec_dir" ] || spec_dir="skills/_shared/templates/design-system-defaults"
specs=$(find "$spec_dir" -maxdepth 1 -name "*.yaml" | sort)
[ -n "$specs" ] || { echo "ERROR: no design-system specs found." >&2; exit 1; }
```

The default bundle ships three files (atomic / molecular / organism). Users
may copy them into `design-system/specs/` and edit. Step-01 reads from the
override dir if present.

### 2. Compute diff (ds-update only)

```bash
if [ "$mode" = "ds-update" ]; then
  prev=$(jq -r '.specs_hash // ""' .design-cache.json 2>/dev/null)
  curr=$(cat $specs | shasum -a 256 | awk '{print $1}')
  [ "$prev" = "$curr" ] && {
    echo "DS specs unchanged. Nothing to do."
    bash skills/_shared/update-progress.sh --project-root="$PWD" \
      --feature-id=_global --step-num=01 --step-name=ds-bootstrap \
      --status=skip --skill=design
    exit 0
  }
fi
```

### 3.a — penpot platform

```bash
for spec in $specs; do
  bash "$helper" add-shapes \
    --file-id="$ds_file_id" \
    --page-name="$ds_components_page" \
    --shapes-file="$spec" \
    --project-root="$PWD"
done
```

`add-shapes` consumes the YAML by way of the helper's spec adapter (already
supported by `penpot-helper.sh add-shapes` via `--shapes-file`). For
`ds-update`, the helper performs upsert by `name` (delete-then-recreate is
acceptable for v0.5; finer reconciliation is a follow-up).

### 3.b — figma platform

Two phases: (a) ensure KB is initialized (ds-init only), (b) compile DS
specs into a unified JS payload routed via the configured transport.

```bash
# ds-init: bootstrap KB structure once.
if [ "$mode" = "ds-init" ]; then
  bash "$helper" --action=ds-init \
    --kb-path="$ds_kb_path" \
    --transport="$ds_transport" \
    --token-env="$ds_token_env"
fi

# ds-init OR ds-update: compile all KB specs → JS, route via transport.
bash "$helper" --action=ds-update \
  --kb-path="$ds_kb_path" \
  --transport="$ds_transport" \
  --token-env="$ds_token_env" \
  ${ds_transport_console_output_js:+--output-js="$ds_transport_console_output_js"}
```

If `$ds_transport == official`, the helper emits a `figma_execute`
descriptor (exit 10) — the dispatcher invokes the MCP tool, MCP runs the JS
in Figma Desktop, returns scene graph IDs inline.

If `$ds_transport == console`, the helper writes the compiled JS to
`--output-js` (or default `<kb-path>/build/out.js`) and the skill surfaces
the path with a "paste in Figma DevTools" instruction:

```bash
output_js=$(jq -r .output_js < "$descriptor")
echo "→ Open Figma DevTools console and paste: $output_js"
AskUserQuestion "Done pasting? [yes/skip]"
```

For `ds-update` Bridge emits a diff JS (component upsert) — same descriptor
flow.

### 4. Cache result

```bash
mkdir -p .design-cache
jq -n \
  --arg hash "$curr" \
  --arg mode "$mode" \
  --argjson specs "$(printf '%s\n' $specs | jq -R . | jq -s .)" \
  '{specs_hash:$hash, mode:$mode, specs:$specs, ts: now | todate}' \
  > .design-cache.json
```

### 5. Save binding to config (ds-init only, optional)

If `ds-init` produced a new DS file (case where binding was empty at
step-00), the helper returns the created `file_id`/`file_key`. Prompt:

```text
AskUserQuestion: "Save this DS binding to config?"
  - Yes → write design.{plat}.{file_id|file_key, file_name}
  - No
```

### 6. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=design --status=ok \
  --extra="{\"mode\":\"$mode\",\"specs_count\":$(echo $specs | wc -w)}"

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id=_global \
  --step-num=01 --step-name=ds-bootstrap --status=ok --skill=design \
  --extra="{\"mode\":\"$mode\"}"
```

## Failure handling

- **Bridge `mockup-compile` fails** (figma) → surface CLI stderr verbatim;
  mark progress `fail`. Common causes: KB path stale (run
  `bridge-ds doctor`), YAML schema invalid (Bridge reports line/column).
- **`add-shapes` rejected** (penpot) → log full MCP error with spec name;
  mark progress `fail`.
- **Transport `console` user skipped paste** → record `pending_paste:true`
  in `.design-cache.json` so `/design --resume` re-prompts.

## Acceptance check

- DS file populated/patched (spot-check: helper `list-pages` returns the
  components page with > 0 shapes added in this run).
- `.design-cache.json` updated with new `specs_hash`.

## Next step

- `mode ∈ {ds-init, ds-update}` → done (skill exits cleanly).
- `mode == mockup` and `--chain-ds` was passed → `step-02-source-resolve.md`.
  This is an undocumented internal flag; users normally re-invoke `/design
  --mode=mockup` explicitly.
