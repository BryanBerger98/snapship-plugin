---
step: 00-init
next_step: 01-filter
description: Parse args, resolve feature_id, load tickets.json + config, resolve wireframe MCP platform.
---

# step-00 — init

Bootstrap a `/wireframe` run for a single feature.

The skill supports multiple wireframe MCP platforms. Step-00 resolves which
one (`frame0` | `penpot`), runs the platform-specific preflight, and
persists `wf_platform` + `$helper` to skill state so every later step is
platform-agnostic.

## Tasks

1. **Parse args**: `--resume`/`-r`, `--feature=PARTIAL`, `--dry-run`.

2. **Resume short-circuit**: delegate to `resume-state.sh`:
   ```bash
   resume_json=$(bash skills/_shared/resume-state.sh next \
     --skill=wireframe \
     --project-root="$PWD" \
     ${feature:+--feature="$feature"})
   ```
   Same rc=0/1/2 handling as `/define`.

3. **Resolve `feature_id`**: same precedence as `/ticket` (single → use it; multi →
   AskUserQuestion; zero → abort with "Run `/define` first").

4. **Require config + load + resolve platform**:
   ```bash
   [ -f "$PWD/snapship.config.json" ] || {
     echo "ERROR: snapship.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   bash skills/_shared/load-config.sh --project-root="$PWD" > /tmp/cfg.json
   wf_platform=$(jq -r '.wireframes.platform // "none"' /tmp/cfg.json)
   ```

   Platform → helper resolution:

   | `wf_platform` | `helper` (set for downstream steps)               | Pre-flight section |
   |---------------|---------------------------------------------------|--------------------|
   | `none`        | n/a — log skip, exit cleanly with progress `skip` | n/a                |
   | `frame0`      | `skills/_shared/frame0-helper.sh`                 | §5.a                |
   | `penpot`      | `skills/_shared/penpot-helper.sh`                 | §5.b                |

5. **Pre-flight MCP** (common to all platforms):
   ```bash
   bash skills/_shared/check-mcp-required.sh --skill=wireframe --project-root="$PWD"
   ```
   The MCP server matching `wf_platform` must be reachable. Surface the
   error verbatim if not.

### 5.a — Pre-flight (frame0 only)

Frame0 desktop must be running and its local HTTP API reachable. The
`export-png` action calls `http://localhost:<frame0_api_port>/execute_command`
(default port `58320`, overridable via `wireframes.frame0_api_port` config).

No further preflight: Frame0's MCP server runs as a child process and the
"current file" is implicit (Frame0 desktop has one active document).

### 5.b — Pre-flight (penpot only)

Penpot MCP **cannot open files programmatically**. The targeted file =
whatever the user has open in the Penpot browser tab where the MCP plugin
is loaded and connected. Verify the binding before any write:

```bash
bash "$helper" --action=get-current-file --project-root="$PWD"
# exit 10 → dispatcher invokes execute_code, receives {id, name}.
# If MCP server replies "No plugin connected" → halt with the message:
#   "Open the target file in Penpot, load the MCP plugin, click
#    'Connect to MCP server'. Re-run /wireframe."
```

Then, if `config.wireframes.penpot_file_id` is set:
- Compare returned `id` to the configured value.
- **Mismatch** → halt with:
  ```
  ERROR: Wrong Penpot file open in browser tab.
    expected: <penpot_file_name> (<penpot_file_id>)
    got:      <current name>     (<current id>)
  Navigate to the correct file in Penpot, then re-run /wireframe.
  ```
- **Match** → continue.

If no `penpot_file_id` in config: show `AskUserQuestion` "Use this Penpot
file: <name> (<id>)?" with options Yes / No / Save to config. "Save to
config" writes the id+name back to `snapship.config.json`.

6. **Persist platform state**: write `wf_platform` + resolved `$helper` path
   to the skill state file so step-02 reads them without re-resolving config.

7. **Validate inputs**:
   - `tickets.json` exists for the feature (run `/ticket` first if not).
   - `prd-feature.md` mentions ≥ 1 wireframe screen ID (otherwise skip —
     feature is non-UI).

8. **Append progress**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="$feature_id" \
     --step-num=00 \
     --step-name=init \
     --status=ok \
     --skill=wireframe
   ```

## Acceptance check

- `feature_id` resolved.
- `tickets.json` exists.
- `wf_platform` resolved (or `none` → skip).
- MCP for resolved platform reachable.
- Platform-specific binding verified (file id for penpot; nothing extra for frame0).

## Next step

→ `step-01-filter.md`
