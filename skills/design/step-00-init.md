---
step: 00-init
next_step: 01b-ds-extract | 01-ds-bootstrap | 02-source-resolve
description: Parse args, resolve feature+mode, load config.design nested, run platform preflight (penpot|figma), auto-link wireframes binding if platform matches. ds-extract is explicit-only (no auto-resolve).
---

# step-00 — init

Bootstrap a `/design` run. Three modes (`ds-init`, `ds-update`, `mockup`)
share this step.

## Tasks

1. **Parse args**: `--resume`/`-r`, `--feature=PARTIAL`, `--mode=ds-extract|ds-init|ds-update|mockup`, `--dry-run`, `--chain-init` (only honored with `--mode=ds-extract`).

2. **Resume short-circuit**: delegate to `resume-state.sh`:
   ```bash
   resume_json=$(bash skills/_shared/resume-state.sh next \
     --skill=design \
     --project-root="$PWD" \
     ${feature:+--feature="$feature"} \
     ${mode:+--mode="$mode"})
   ```
   Same rc=0/1/2 handling as `/wireframe`. Resume state is keyed
   `(skill=design, feature_id, mode)` so the three modes resume independently.

3. **Require config + load + resolve platform**:
   ```bash
   [ -f "$PWD/snapship.config.json" ] || {
     echo "ERROR: snapship.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   bash skills/_shared/load-config.sh --project-root="$PWD" > /tmp/cfg.json
   ds_platform=$(jq -r '.design.platform // "none"' /tmp/cfg.json)

   case "$ds_platform" in
     penpot)
       ds_file_id=$(jq -r '.design.penpot.file_id // ""' /tmp/cfg.json)
       ds_file_name=$(jq -r '.design.penpot.file_name // ""' /tmp/cfg.json)
       ds_export_dir=$(jq -r '.design.penpot.export_dir // ""' /tmp/cfg.json)
       ds_components_page=$(jq -r '.design.penpot.design_system_page // "Components"' /tmp/cfg.json)
       export_format=$(jq -r '.design.export_format // "png"' /tmp/cfg.json)
       ;;
     figma)
       ds_file_key=$(jq -r '.design.figma.file_key // ""' /tmp/cfg.json)
       ds_file_name=$(jq -r '.design.figma.file_name // ""' /tmp/cfg.json)
       ds_token_env=$(jq -r '.design.figma.token_env // "FIGMA_ACCESS_TOKEN"' /tmp/cfg.json)
       ds_kb_path=$(jq -r '.design.figma.bridge_kb_path // ".claude/product/design-system/kb"' /tmp/cfg.json)
       ds_transport=$(jq -r '.design.figma.bridge_transport // "official"' /tmp/cfg.json)
       export_format=$(jq -r '.design.export_format // "png"' /tmp/cfg.json)
       ;;
     none)
       echo "design.platform = none → skipping /design"
       bash skills/_shared/update-progress.sh --project-root="$PWD" \
         --feature-id="${feature_id:-_global}" --step-num=00 --step-name=init \
         --status=skip --skill=design
       exit 0
       ;;
     *)
       echo "ERROR: unsupported design.platform: $ds_platform (expected penpot|figma|none)" >&2
       exit 1
       ;;
   esac

   helper="skills/_shared/$([ "$ds_platform" = "figma" ] && echo figma-bridge-helper.sh || echo penpot-helper.sh)"
   ```

4. **Resolve mode** (the mode resolver):
   - If `--mode=ds-extract` → route directly to `step-01b-ds-extract.md`.
     **Skip** auto-detection — `ds-extract` is never inferred (it would
     clobber Figma edits with re-extracted YAML). Skip platform preflight
     for the dry-run path; require it only when `--chain-init` is set.
   - Else if `--mode` provided → use it.
   - Else, auto-detect by signal precedence:

   | Signal                                                                     | Mode      |
   |----------------------------------------------------------------------------|-----------|
   | DS file binding empty AND `_shared/templates/design-system-defaults/*.yaml` exists | `ds-init` |
   | DS file binding set AND `design-system/specs/**.yaml` diff vs `.design-cache.json` shows changes | `ds-update` |
   | `--feature` set OR a single feature has `tickets.json` with UI tickets unflagged | `mockup`  |

   If multiple signals match → `AskUserQuestion`:
   > "Multiple modes possible. Which one?"
   > Options: `ds-init`, `ds-update`, `mockup`.

   If no signal matches → abort: `"No work to do. Run /ticket first (for
   mockup) or add a DS spec under design-system/specs/ (for ds-init)."`.

5. **Resolve `feature_id`** (mode = `mockup` only): same precedence as
   `/ticket` (single → use it; multi → `AskUserQuestion`; zero → abort with
   "Run `/define` first").

6. **Pre-flight MCP** (common, both platforms):
   ```bash
   bash skills/_shared/check-mcp-required.sh --skill=design --project-root="$PWD"
   ```
   The MCP server matching `ds_platform` must be reachable. Surface the error
   verbatim if not.

### 6.a — Pre-flight (penpot only)

Same plugin-binding check as `/wireframe penpot`:

```bash
bash "$helper" --action=get-current-file
# exit 10 → dispatcher invokes execute_code → {id, name}
```

If `$ds_file_id` empty → run the **auto-link** flow (§7). Otherwise compare
returned `id` to `$ds_file_id`. Mismatch → halt with binding error.

### 6.b — Pre-flight (figma only)

Figma Desktop + Desktop Bridge plugin connected. Token chargé depuis
`.env.snapship` racine projet (jamais depuis shell env directement — secrets
isolés per-project, gitignored). Clé par défaut `FIGMA_ACCESS_TOKEN`, override
via `design.figma.token_env`.

```bash
ds_token=$(bash skills/_shared/load-env.sh \
  --project-root="$PWD" --key="$ds_token_env" 2>/dev/null || true)
if [ -z "$ds_token" ]; then
  echo "ERROR: $ds_token_env absent de $PWD/.env.snapship." >&2
  echo "Créer le fichier avec: $ds_token_env=figd_<votre-pat-figma>" >&2
  echo "Token généré via Figma → Settings → Personal access tokens." >&2
  exit 1
fi
# Export pour figma-console-mcp + bridge-ds CLI (lus depuis env par enfants).
export "$ds_token_env=$ds_token"

bash skills/_shared/figma-helper.sh --action=get-current-file --file-key="$ds_file_key"
# exit 10 → dispatcher invokes figma_execute → {id: figma.fileKey, name: figma.root.name}
```

If `$ds_file_key` empty → **auto-link** flow (§7). Otherwise mismatch → halt
with binding error.

Bridge CLI sanity check (only modes `ds-init`/`ds-update`/`mockup` on
figma):
```bash
bash "$helper" --action=ds-init --kb-path="$ds_kb_path" --dry-run \
  || { echo "ERROR: bridge-ds CLI unavailable. Install via npm i -g @noemuch/bridge-ds." >&2; exit 1; }
```

## 7. Auto-link from wireframes binding

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

## 8. Persist platform state

Write `ds_platform`, resolved `$helper` path, mode (`ds-init|ds-update|mockup`),
and all resolved nested values (`ds_file_id`, `ds_file_key`, `ds_kb_path`,
`ds_transport`, `export_format`, …) to the skill state file. Later steps read
from state — they do NOT re-resolve config.

## 9. Validate inputs (mode-dependent)

- **`ds-init`** — at least one YAML under
  `_shared/templates/design-system-defaults/*.yaml` (or
  `design-system/specs/*.yaml` if user-overridden).
- **`ds-update`** — `$ds_file_id`/`$ds_file_key` set, `.design-cache.json`
  exists with prior DS state to diff against.
- **`mockup`** — `tickets.json` exists for the feature. `prd-feature.md`
  mentions ≥ 1 screen ID. Optional: `.wireframes-draft.json` exists (signals
  reuse of wireframes screens — see step-02).

## 10. Append progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id="${feature_id:-_global}" \
  --step-num=00 \
  --step-name=init \
  --status=ok \
  --skill=design \
  --extra="{\"mode\":\"$mode\"}"
```

## Acceptance check

- `ds_platform` resolved (or `none` → skip).
- MCP for `ds_platform` reachable.
- Mode resolved (`ds-init`, `ds-update`, or `mockup`).
- Platform binding verified (file_id or file_key match, or auto-link applied).
- Mode-specific inputs validated.

## Next step

- `mode == ds-extract` → `step-01b-ds-extract.md` (then optionally chains into `step-01-ds-bootstrap.md` with `--chain-init`)
- `mode ∈ {ds-init, ds-update}` → `step-01-ds-bootstrap.md`
- `mode == mockup` → `step-02-source-resolve.md`
