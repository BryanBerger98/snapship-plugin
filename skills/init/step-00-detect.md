---
step: 00-detect
next_step: 01-write
description: Parse args, detect MCP availability, probe project structure, render answers via AskUserQuestion (or autonomous defaults).
---

# step-00 — detect

Probe the environment and resolve answers for every required config field.

## Tasks

1. **Parse args** from `/artysan:init`. Recognize `--auto`/`-a`, `--lang=fr|en`,
   `--force`. Default `lang=fr`, `auto=false`, `force=false`.

2. **Project root sanity**: confirm `$PWD` looks like a project root (presence of
   `.git`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or
   `composer.json`). If none found, ask the user to confirm before proceeding.

3. **Existing config guard**: if `$PWD/artysan.config.json` exists and `--force`
   is not passed, abort with:
   ```
   ERROR: artysan.config.json already exists. Re-run with --force to overwrite,
   or run /artysan:define to start a feature.
   ```
   Do **not** write progress; just exit.

4. **MCP availability**: detect which MCP servers are reachable in the current
   Claude Code session. The orchestrator should look at the active session's
   MCP servers (typically `affine`, `frame0`, `playwright`, `code-review-graph`)
   and pass them as a comma-separated list into setup-config.sh:
   ```bash
   # Example — replace with actual session MCP list
   AVAILABLE="${ARTYSAN_MCP_AVAILABLE:-affine,frame0}"
   detected=$(bash skills/_shared/setup-config.sh --detect \
     --project-root="$PWD" \
     --available="$AVAILABLE")
   ```
   `detected` is JSON: `{repository:{platform,url}, tickets:{platform},
   documentation:{platform}, wireframes:{platform}, defaults:{lang}}`.

5. **Resolve answers**:

   - **Autonomous (`--auto`)**: use `detected` as-is. Pass `--auto-mode=true` in
     step-01 so setup-config.sh fails loud if any required field is empty
     (e.g. no MCP detected for docs).

   - **Interactive (default)**: drive `AskUserQuestion` for each field, using
     the detected value as the recommended option. Show the source signal
     (e.g. ".git/config remote → github") so the user can override knowingly.

     Required questions (skip the question when the detected value is
     unambiguous and the user is in `-a` mode):

     | Field | Header | Options |
     |-------|--------|---------|
     | `repository.platform` | Repo platform | github, gitlab |
     | `tickets.platform` | Tickets | github, gitlab, jira |
     | `documentation.platform` | Docs | affine, notion |
     | `wireframes.platform` | Wireframes | frame0 |
     | `defaults.lang` | Lang | fr, en |

     Build a single JSON object with every answered field, scoped under the
     correct config section:
     ```json
     {
       "repository": { "platform": "github", "url": "https://github.com/..." },
       "tickets":    { "platform": "github" },
       "documentation": { "platform": "affine" },
       "wireframes": { "platform": "frame0" },
       "defaults":   { "lang": "fr" }
     }
     ```
     Save it to a transient `$ANSWERS_JSON` shell variable for step-01.

6. **Hand off** to step-01-write with:
   - `$ANSWERS_JSON` (or empty if `--auto`)
   - `$AUTO` (true/false)
   - `$FORCE` (true/false)
   - `$LANG_OVERRIDE` (or empty)

## Variables to record

| Var | Source | Used by |
|-----|--------|---------|
| `auto` | `--auto`/`-a` | step-01 (`--auto-mode`) |
| `force` | `--force` | step-01 (`--force`) |
| `lang` | `--lang` or detected or asked | step-01 (`--lang`) |
| `answers_json` | merged AskUserQuestion answers | step-01 (`--from-answers`) |

## Acceptance check

- `detected` JSON parsed without error.
- All required fields resolved (either from detection or user answers).

## Next step

→ `step-01-write.md`
