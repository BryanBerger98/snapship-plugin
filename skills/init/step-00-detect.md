---
step: 00-detect
next_step: 01-write
description: Parse args, detect MCP availability, probe project structure, render answers via AskUserQuestion (or autonomous defaults).
---

# step-00 — detect

Probe the environment and resolve answers for every required config field.

## Communication language (`defaults.lang`)

`/snap:init` may run before `snap.config.json` exists. Resolve the language from
the `--lang=` arg if given, else from an existing config, else fall back to
`fr`, then respond to the user in it for the whole skill run:

```bash
SNAP_LANG="${lang_arg:-$(jq -r '.defaults.lang // "fr"' "$PWD/snap.config.json" 2>/dev/null || echo fr)}"
SNAP_LANG="${SNAP_LANG:-fr}"
```

**Directive**: communicate with the user in `$SNAP_LANG` (`fr` = français,
`en` = English, …). Presentation directive only — never translate config keys,
file paths, or code identifiers.

## Progress persistence (`defaults.save_mode`)

`/snap:init` runs before the config exists, so `save_mode` is the default
`true` here (read from any existing config as a courtesy, else `true`):

```bash
save_mode=$(jq -r '.defaults.save_mode // true' "$PWD/snap.config.json" 2>/dev/null || echo true)
```

**Directive**: pass `--save-mode="$save_mode"` to every `progress.sh`
`start`/`step`/`finish` call in this skill (`_global` story-id). When
`save_mode=false` those writes become no-ops.

## Tasks

1. **Parse args** from `/snap:init`. Recognize `--auto`/`-a`, `--lang=fr|en`,
   `--force`. Default `lang=fr`, `auto=false`, `force=false`.

2. **Project root sanity** : confirm `$PWD` looks like a project root (presence of
   `.git`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or
   `composer.json`). If none found, ask the user to confirm before proceeding.

3. **Existing config guard** : if `$PWD/snap.config.json` exists and `--force`
   is not passed, abort with :
   ```
   ERROR: snap.config.json already exists. Re-run with --force to overwrite,
   or run /snap:define to start a feature.
   ```
   Do **not** write progress; just exit.

4. **MCP availability** : detect which MCP servers are reachable in the current
   Claude Code session. Pass the comma-separated list into setup-config.sh :
   ```bash
   # Tipical platforms across categories:
   #   docs       : notion, affine
   #   design     : figma, penpot, frame0
   #   tickets    : linear, jira, github, gitlab (via repo platform CLI)
   #   repo       : github, gitlab
   AVAILABLE="${SNAP_MCP_AVAILABLE:-affine,frame0}"
   detected=$(bash skills/_shared/setup-config.sh --detect \
     --project-root="$PWD" \
     --available="$AVAILABLE")
   ```
   `detected` is JSON :
   `{repository:{platform,url}, tickets:{platform}, documentation:{platform},
   design:{platform}, wireframes:{platform}, defaults:{lang}}`.

5. **Resolve answers** :

   - **Autonomous (`--auto`)** : use `detected` as-is. Pass `--auto-mode=true` in
     step-01 so setup-config.sh fails loud if any required field is empty
     (e.g. no MCP detected for docs).

   - **Interactive (default)** : drive `AskUserQuestion` for each field, using
     the detected value as the recommended option. Show the source signal
     (e.g. `.git/config remote → github`) so the user can override knowingly.

     Required questions (skip the question when the detected value is
     unambiguous and the user is in `-a` mode) :

     | Field | Header | Options |
     |-------|--------|---------|
     | `repository.platform`     | Repo platform | github, gitlab |
     | `tickets.platform`        | Tickets       | linear, jira, github, gitlab, none |
     | `documentation.platform`  | Docs          | notion, affine, none |
     | `design.platform`         | Design        | figma, penpot, none |
     | `wireframes.platform`     | Wireframes    | frame0, figma, penpot, none |
     | `defaults.lang`           | Lang          | fr, en |

     **Doc paths** — only ask if `documentation.platform != "none"` :

     | Field | Header | Default |
     |-------|--------|---------|
     | `documentation.paths.functional_root` | Functional root | `Product Docs` |
     | `documentation.paths.prd_root`        | PRD archive root | `Change Requests` |

     Both are root page titles on the doc platform. `functional_root` holds the
     living domain → user journey hierarchy. `prd_root` archives PRD pages by
     date (`{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`).

     Build a single JSON object with every answered field, scoped under the
     correct config section :
     ```json
     {
       "repository":    { "platform": "github", "url": "https://github.com/..." },
       "tickets":       { "platform": "linear" },
       "documentation": {
         "platform": "notion",
         "paths": {
           "functional_root": "Product Docs",
           "prd_root": "Change Requests"
         }
       },
       "design":        { "platform": "figma" },
       "wireframes":    { "platform": "frame0" },
       "defaults":      { "lang": "fr" }
     }
     ```
     Save it to a transient `$ANSWERS_JSON` shell variable for step-01.

     Skip the `paths` block entirely when `documentation.platform == "none"`.
     Skip `tickets.platform` enforcement — `none` is valid but `/snap:ticket`
     will BLOCK with a clear message until the user re-runs `/snap:init --force`
     to set a tracker (per refactor v1.0 decision).

6. **Hand off** to step-01-write with :
   - `$ANSWERS_JSON` (or empty if `--auto`)
   - `$AUTO` (true/false)
   - `$FORCE` (true/false)
   - `$LANG_OVERRIDE` (or empty)

## Variables to record

| Var | Source | Used by |
|-----|--------|---------|
| `auto`         | `--auto`/`-a` | step-01 (`--auto-mode`) |
| `force`        | `--force` | step-01 (`--force`) |
| `lang`         | `--lang` or detected or asked | step-01 (`--lang`) |
| `answers_json` | merged AskUserQuestion answers | step-01 (`--from-answers`) |

## Acceptance check

- `detected` JSON parsed without error.
- All required fields resolved (either from detection or user answers).

## Next step

→ `step-01-write.md`
