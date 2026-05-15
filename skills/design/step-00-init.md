---
step: 00-init
next_step: 01-source-resolve
description: Parse args, resolve target ticket(s), load config.design nested, run platform preflight (penpot|figma), auto-link wireframes binding if platform matches.
---

# step-00 — init

Bootstrap a `/design` run. Targets one ticket or every UI ticket of a feature.

## Tasks

1. **Parse args**: `--resume`/`-r`, positional `<ticket-id|feature-id>`,
   `--dry-run`, `--no-wireframe-reuse`.

2. **Resume short-circuit**: delegate to `progress.sh resume`:
   ```bash
   resume_line=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" \
     --skill=design \
     --feature-id="${feature_id:-_global}")
   ```
   Same rc=0/1/2 handling as `/wireframe`.

3. **Resolve target**: same precedence as `/qa`.
   - **Empty positional** → `AskUserQuestion` enumerating UI tickets not yet
     flagged with `design_url`.
   - **Ticket-shaped** → single-ticket mode. Resolve the owning `feature_id`
     from the ticket's `tickets.json`.
   - **Feature-shaped** → multi-ticket mode (every UI ticket of the feature).

   The set of targeted `local_id`s is persisted to skill state as
   `target_tickets[]`; step-01 builds the screen list from exactly these.

4. **Require config + load + resolve platform**:
   ```bash
   [ -f "$PWD/snapship.config.json" ] || {
     echo "ERROR: snapship.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   ds_platform=$(jq -r '.design.platform // "none"' <<<"$CONFIG_JSON")

   case "$ds_platform" in
     penpot)
       ds_file_id=$(jq -r '.design.penpot.file_id // ""' <<<"$CONFIG_JSON")
       ds_file_name=$(jq -r '.design.penpot.file_name // ""' <<<"$CONFIG_JSON")
       ds_export_dir=$(jq -r '.design.penpot.export_dir // ""' <<<"$CONFIG_JSON")
       ds_components_page=$(jq -r '.design.penpot.design_system_page // "Components"' <<<"$CONFIG_JSON")
       export_format=$(jq -r '.design.export_format // "png"' <<<"$CONFIG_JSON")
       ds_source=$(jq -r '.design.mode_defaults.design_system_source // "auto"' <<<"$CONFIG_JSON")
       ;;
     figma)
       ds_file_key=$(jq -r '.design.figma.file_key // ""' <<<"$CONFIG_JSON")
       ds_file_name=$(jq -r '.design.figma.file_name // ""' <<<"$CONFIG_JSON")
       ds_token_env=$(jq -r '.design.figma.token_env // "FIGMA_ACCESS_TOKEN"' <<<"$CONFIG_JSON")
       export_format=$(jq -r '.design.export_format // "png"' <<<"$CONFIG_JSON")
       ds_source=$(jq -r '.design.mode_defaults.design_system_source // "auto"' <<<"$CONFIG_JSON")
       ;;
     none)
       echo "design.platform = none → skipping /design"
       bash skills/_shared/progress.sh step --project-root="$PWD" \
         --skill=design --feature-id="${feature_id:-_global}" \
         --step-num=00 --step-name=init --status=skip
       exit 0
       ;;
     *)
       echo "ERROR: unsupported design.platform: $ds_platform (expected penpot|figma|none)" >&2
       exit 1
       ;;
   esac

   helper="skills/_shared/$([ "$ds_platform" = "figma" ] && echo figma-helper.sh || echo penpot-helper.sh)"
   ```

   `/design figma` uses **the same helper as `/wireframe figma`** —
   `figma-helper.sh` — and the same Desktop Bridge plugin. No separate
   tooling.

5. **Pre-flight MCP** (common, both platforms):
   ```bash
   bash skills/_shared/check-mcp-required.sh --skill=design --project-root="$PWD"
   ```
   The MCP server matching `ds_platform` must be reachable. Surface the error
   verbatim if not.

### 5.a — Pre-flight (penpot only)

Same plugin-binding check as `/wireframe penpot`:

```bash
bash "$helper" --action=get-current-file
# exit 10 → dispatcher invokes execute_code → {id, name}
```

If `$ds_file_id` empty → run the **auto-link** flow (§6). Otherwise compare
returned `id` to `$ds_file_id`. Mismatch → halt with binding error.

### 5.b — Pre-flight (figma only)

Same check as `/wireframe figma`. Figma Desktop + Desktop Bridge plugin
connected (WebSocket ports 9223–9232 auto-discovered by `figma-console-mcp`).
Token chargé depuis `.env.snapship` racine projet (jamais depuis shell env
directement — secrets isolés per-project, gitignored). Clé par défaut
`FIGMA_ACCESS_TOKEN`, override via `design.figma.token_env`.

```bash
ds_token=$(bash skills/_shared/load-env.sh \
  --project-root="$PWD" --key="$ds_token_env" 2>/dev/null || true)
if [ -z "$ds_token" ]; then
  echo "ERROR: $ds_token_env absent de $PWD/.env.snapship." >&2
  echo "Créer le fichier avec: $ds_token_env=figd_<votre-pat-figma>" >&2
  echo "Token généré via Figma → Settings → Personal access tokens." >&2
  exit 1
fi
# Export pour figma-console-mcp (lu depuis env pour ses fallbacks REST).
export "$ds_token_env=$ds_token"

bash "$helper" --action=get-current-file --file-key="$ds_file_key"
# exit 10 → dispatcher invokes figma_execute → {id: figma.fileKey, name: figma.root.name}
```

If `$ds_file_key` empty → **auto-link** flow (§6). Otherwise mismatch → halt
with binding error.

## 6. Auto-link from wireframes binding

If `$ds_file_id`/`$ds_file_key` is empty **and**
`wireframes.platform == design.platform` **and** the matching wireframes
binding is populated, raise:

```text
AskUserQuestion:
  "Reuse wireframes binding for /design?
   wireframes.{plat}.file_id = <wireframes id/key>
   wireframes.{plat}.file_name = <name>"
  Options:
    - Yes, reuse same file
    - No, separate design file (prompt for binding)
    - Save reuse choice to config (writes design.{plat}.{file_id,file_key,file_name})
```

If `wireframes.platform != design.platform` or the wireframes binding is also
empty → plain `AskUserQuestion` asking for the design file binding (current
opened file in browser/Desktop), same UX as `/wireframe` step-00.

## 7. Persist platform state

Write `ds_platform`, resolved `$helper` path, `target_tickets[]`,
`feature_id`, and all resolved nested values (`ds_file_id`, `ds_file_key`,
`ds_components_page`, `ds_source`, `export_format`, …) to the skill state
file. Later steps read from state — they do NOT re-resolve config.

## 8. Validate inputs

- `.snap/tickets/${feature_id}.json` exists (run `/ticket` first if not).
- At least one targeted ticket is a UI ticket (per
  `filter-ui-tickets.sh`) — otherwise mark progress `skip` with note
  `no UI tickets`.
- Optional: manifest `.refs.wireframes_gallery.sync_status = "synced"`
  (signals reusable wireframes screens — see step-01).

## 9. Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=design \
  --feature-id="$feature_id" \
  --step-num=00 \
  --step-name=init \
  --status=ok
```

## Acceptance check

- `ds_platform` resolved (or `none` → skip).
- MCP for `ds_platform` reachable.
- `feature_id` + `target_tickets[]` resolved.
- Platform binding verified (file_id or file_key match, or auto-link applied).
- At least one targeted UI ticket (else skip).

## Next step

→ `step-01-source-resolve.md`
