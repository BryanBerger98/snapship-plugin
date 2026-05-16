---
step: 00-init
next_step: 01-filter
description: Parse args, resolve feature_id, load tickets.json + config, resolve wireframe MCP platform.
---

# step-00 — init

Bootstrap a `/wireframe` run for a single feature.

The skill supports multiple wireframe MCP platforms. Step-00 resolves which
one (`frame0` | `penpot` | `figma`), runs the platform-specific preflight, and
persists `wf_platform` + `$helper` + resolved platform config (api_port,
file_id, file_key, …) to skill state so every later step is platform-agnostic.
Helpers are context-agnostic since v0.5 — step-00 reads the nested config
once and downstream steps pass values explicitly.

## Tasks

1. **Parse args**: `--resume`/`-r`, `--feature=PARTIAL`, `--dry-run`.

2. **Resume short-circuit**: delegate to `progress.sh resume`:
   ```bash
   resume_line=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" \
     --skill=wireframe \
     --feature-id="${feature:-_global}")
   ```
   Same rc=0/1/2 handling as `/define`.

3. **Resolve `feature_id`**: same precedence as `/ticket` (single → use it; multi →
   AskUserQuestion; zero → abort with "Run `/define` first").

4. **Require config + load + resolve platform**:
   ```bash
   [ -f "$PWD/snap.config.json" ] || {
     echo "ERROR: snap.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   wf_platform=$(jq -r '.wireframes.platform // "none"' <<<"$CONFIG_JSON")

   # Resolve platform-specific nested values once — helpers no longer read config.
   case "$wf_platform" in
     frame0)
       api_port=$(jq -r '.wireframes.frame0.api_port // 58320' <<<"$CONFIG_JSON")
       export_format=$(jq -r '.wireframes.export_format // "png"' <<<"$CONFIG_JSON")
       ;;
     penpot)
       penpot_file_id=$(jq -r '.wireframes.penpot.file_id // ""' <<<"$CONFIG_JSON")
       penpot_file_name=$(jq -r '.wireframes.penpot.file_name // ""' <<<"$CONFIG_JSON")
       penpot_export_dir=$(jq -r '.wireframes.penpot.export_dir // ""' <<<"$CONFIG_JSON")
       export_format=$(jq -r '.wireframes.export_format // "png"' <<<"$CONFIG_JSON")
       ;;
     figma)
       figma_file_key=$(jq -r '.wireframes.figma.file_key // ""' <<<"$CONFIG_JSON")
       figma_file_name=$(jq -r '.wireframes.figma.file_name // ""' <<<"$CONFIG_JSON")
       figma_token_env=$(jq -r '.wireframes.figma.token_env // "FIGMA_ACCESS_TOKEN"' <<<"$CONFIG_JSON")
       export_format=$(jq -r '.wireframes.export_format // "png"' <<<"$CONFIG_JSON")
       ;;
   esac
   ```

   Platform → helper resolution:

   | `wf_platform` | `helper` (set for downstream steps)               | Pre-flight section |
   |---------------|---------------------------------------------------|--------------------|
   | `none`        | n/a — log skip, exit cleanly with progress `skip` | n/a                |
   | `frame0`      | `skills/_shared/frame0-helper.sh`                 | §5.a               |
   | `penpot`      | `skills/_shared/penpot-helper.sh`                 | §5.b               |
   | `figma`       | `skills/_shared/figma-helper.sh`                  | §5.c               |

5. **Pre-flight MCP** (common to all platforms):
   ```bash
   bash skills/_shared/check-mcp-required.sh --skill=wireframe --project-root="$PWD"
   ```
   The MCP server matching `wf_platform` must be reachable. Surface the
   error verbatim if not.

### 5.a — Pre-flight (frame0 only)

Frame0 desktop must be running and its local HTTP API reachable. The
`export-png` action calls `http://localhost:<api_port>/execute_command`
(default `58320`, configurable via `wireframes.frame0.api_port`). The
resolved value is in shell var `$api_port` (set in step 4).

No further preflight: Frame0's MCP server runs as a child process and the
"current file" is implicit (Frame0 desktop has one active document).

### 5.b — Pre-flight (penpot only)

Penpot MCP **cannot open files programmatically**. The targeted file =
whatever the user has open in the Penpot browser tab where the MCP plugin
is loaded and connected. Verify the binding before any write:

```bash
bash "$helper" --action=get-current-file
# exit 10 → dispatcher invokes execute_code, receives {id, name}.
# If MCP server replies "No plugin connected" → halt with the message:
#   "Open the target file in Penpot, load the MCP plugin, click
#    'Connect to MCP server'. Re-run /wireframe."
```

Then, if `$penpot_file_id` (resolved from `wireframes.penpot.file_id`) is set:
- Compare returned `id` to `$penpot_file_id`.
- **Mismatch** → halt with:
  ```
  ERROR: Wrong Penpot file open in browser tab.
    expected: $penpot_file_name ($penpot_file_id)
    got:      <current name>    (<current id>)
  Navigate to the correct file in Penpot, then re-run /wireframe.
  ```
- **Match** → continue.

If `$penpot_file_id` empty: show `AskUserQuestion` "Use this Penpot
file: <name> (<id>)?" with options Yes / No / Save to config. "Save to
config" writes the id+name to `wireframes.penpot.{file_id,file_name}`.

### 5.c — Pre-flight (figma only)

Figma Desktop must be running with the **Desktop Bridge** plugin loaded and
connected (WebSocket ports 9223–9232 auto-discovered by `figma-console-mcp`).
The MCP server itself is registered globally and reaches Figma through that
bridge plugin.

Verify the connection by calling `get-current-file` — the JS executed via
`figma_execute` returns `{id: figma.fileKey, name: figma.root.name}` from
whatever file is open in Figma Desktop:

```bash
bash "$helper" --action=get-current-file --file-key="$figma_file_key"
# exit 10 → dispatcher invokes figma_execute; on connection failure surface
# the MCP error verbatim plus this hint:
#   "Open Figma Desktop, install/enable the 'Desktop Bridge' plugin
#    (Plugins → Browse → 'Desktop Bridge'), open the target file, then
#    re-run /wireframe."
```

Then, if `$figma_file_key` (from `wireframes.figma.file_key`) is set:
- Compare returned `id` to `$figma_file_key`.
- **Mismatch** → halt with:
  ```
  ERROR: Wrong Figma file open in Desktop.
    expected: $figma_file_name ($figma_file_key)
    got:      <current name>   (<current id>)
  Open the correct file in Figma Desktop, then re-run /wireframe.
  ```
- **Match** → continue.

If `$figma_file_key` empty: `AskUserQuestion` "Use this Figma file: <name>
(<id>)?" — Yes / No / Save to config. "Save to config" writes
`wireframes.figma.{file_key,file_name}`.

Also load the token from `.env.snap` at project root (clé par défaut
`FIGMA_ACCESS_TOKEN`, override via `wireframes.figma.token_env`). Le fichier
`.env.snap` est gitignored — secrets isolés per-project. `figma-console-mcp`
lit la var env pour ses fallbacks REST :
```bash
figma_token=$(bash skills/_shared/load-env.sh \
  --project-root="$PWD" --key="$figma_token_env" 2>/dev/null || true)
if [ -z "$figma_token" ]; then
  echo "ERROR: $figma_token_env absent de $PWD/.env.snap." >&2
  echo "Créer le fichier avec: $figma_token_env=figd_<votre-pat-figma>" >&2
  echo "Token généré via Figma → Settings → Personal access tokens." >&2
  exit 1
fi
export "$figma_token_env=$figma_token"
```

6. **Persist platform state**: write `wf_platform`, resolved `$helper` path,
   and all resolved nested config values (`api_port`, `penpot_file_id`,
   `figma_file_key`, `export_format`, etc.) to the skill state file so step-02
   reads them without re-resolving config and passes them explicitly to the
   context-agnostic helpers.

7. **Validate inputs**:
   - `.snap/tickets/${feature_id}.json` exists (run `/ticket` first if not).
   - PRD (`.snap/PRDs/${feature_id}.md` or rehydrated from `manifest.refs.prd`)
     mentions ≥ 1 wireframe screen ID (otherwise skip — feature is non-UI).

8. **Append progress**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=wireframe \
     --feature-id="$feature_id" \
     --step-num=00 \
     --step-name=init \
     --status=ok
   ```

## Acceptance check

- `feature_id` resolved.
- `.snap/tickets/${feature_id}.json` exists.
- `wf_platform` resolved (or `none` → skip).
- MCP for resolved platform reachable.
- Platform-specific binding verified:
  - frame0: HTTP API reachable on `$api_port`.
  - penpot: plugin connected + file id match (or AskUserQuestion).
  - figma: Desktop Bridge plugin connected + file key match (or AskUserQuestion) + token env set.

## Next step

→ `step-01-filter.md`
