# Config — `snapship.config.json`

**Location:** project root (committable, shared with team).

**Sections:** `repository`, `tickets`, `documentation`, `wireframes`, `design`, `testing`, `naming`, `ai`, `develop`, `qa`, `lifecycle_scripts`, `templates`, `defaults`.

## Full schema

```jsonc
{
  "$schema": "./.snap/schemas/config.schema.json",
  "version": "1.0",
  // setup-config.sh copies bundled schemas `_shared/schemas/*.schema.json` → `.snap/schemas/` on first run
  // load-config.sh validates config against schema (Ajv or jsonschema CLI). Explicit fail if invalid.
  "repository": {
    "platform": "github",                  // github | gitlab
    "http_url": "https://github.com/org/repo.git",
    "ssh_url": "git@github.com:org/repo.git",
    "default_branch": "main",
    "protected_branches": ["main", "develop"]   // refuses direct commit/push
    // merge_method dropped in v1 — user merges PR manually post-creation
    // `pr_template_path` removed — use `templates.pr` (see `templates` section)
  },
  "tickets": {
    "platform": "jira",                    // github | gitlab | jira | inherit
    "url": "https://company.atlassian.net/browse/PROJ",
    "default_labels": ["snap"],
    "jira": {                              // section used only if platform=jira
      "project_key": "PROJ",
      "default_issue_type": "Story",
      "workflow_states": {                  // platform state mapping
        "todo": "To Do",
        "in_progress": "In Progress",
        "review": "In Review",
        "done": "Done"
      },
      "transitions": {                      // JIRA transition names
        "start": "Start Progress",
        "review": "Submit for Review",
        "complete": "Done"
      }
    }
  },
  "documentation": {
    "platform": "affine",                  // affine | notion
    "url": "https://app.affine.pro",
    "workspace": {
      "id": "ws-abc",
      "root_page_id": "page-xyz"
    },
    "templates": {
      "prd_global": "tpl-id-1",
      "prd_feature": "tpl-id-2",
      "wireframes_gallery": "tpl-id-3"
    },
    "auto_publish": true,                  // publish vs draft
    "page_naming": {
      "prd_global": "PRD - {product_name}",
      "prd_feature": "{feature_id} - {feature_name}",
      "wireframes_gallery": "Wireframes - {feature_name}"
    }
  },
  "wireframes": {                          // optional, absent = /wireframe disabled
    "platform": "frame0",                  // frame0 | penpot | figma
    "export_format": "png",                // png | svg | pdf
    "export_scale": 2,                     // 1x, 2x, 3x (retina, ignored by export-png)
    "naming_pattern": "{feature_id}-{screen_name}",
    "frame0": {                            // read only if platform=frame0
      "api_port": 58320,                   // Frame0 desktop HTTP API port (export-png bypass)
      "export_source_dir": null            // absolute, by default resolved at runtime (Frame0 cwd)
    },
    "penpot": {                            // read only if platform=penpot
      "export_dir": null,                  // absolute (Penpot MCP requires absolute filePath); runtime default = features/{id}/wireframes/
      "file_id": null,                     // UUID of the targeted file (step-00 preflight)
      "file_name": null                    // human name for mismatch error message
    },
    "figma": {                             // read only if platform=figma
      "file_key": null,                    // targeted file key (step-00 preflight vs figma.fileKey)
      "file_name": null,                   // human name for mismatch
      "token_env": "FIGMA_ACCESS_TOKEN"    // env variable for the personal Figma token
    }
  },
  "design": {                              // optional, absent = /design disabled. Block parallel to wireframes
    "platform": "penpot",                  // penpot | figma (frame0 excluded — low-fi only)
    "export_format": "png",                // png | svg | pdf
    "naming_pattern": "{feature_id}-{screen_name}-design",
    "mode_defaults": {
      "mockup_canvas": "mobile-portrait",  // mobile-portrait | mobile-landscape | desktop | tablet
      "design_system_source": "auto"       // auto | file | none — DS read for reference only, never written
    },
    "penpot": {                            // read only if platform=penpot. Helper reused: penpot-helper.sh
      "file_id": null,
      "file_name": null,
      "export_dir": null,
      "design_system_page": "Components"   // Penpot page read as visual reference — /design never writes to it
    },
    "figma": {                             // read only if platform=figma. Helper: figma-helper.sh (same helper as /wireframe figma)
      "file_key": null,
      "file_name": null,
      "token_env": "FIGMA_ACCESS_TOKEN"
    }
  },
  "testing": {
    "test_command": "pnpm test",
    "typecheck_command": "pnpm typecheck",
    "lint_command": "pnpm lint",
    "format_command": "pnpm format"
  },
  "naming": {
    // feature_id format hardcoded: NN-kebab (e.g. 01-auth) — not configurable
    "feature_slug_max_length": 40,         // slug truncation
    "branch_pattern": "{type}/{ticket_id}-{slug}",
    "commit_pattern": "{type}({scope}): {message}",
    "ticket_id_regex": "[A-Z]+-[0-9]+"     // extract ID from branch/commit
  },
  "ai": {
    "max_parallel_agents": 5,
    "mcp_servers_required": [              // fail-fast at startup if absent
      "affine-mcp-server",
      "frame0-mcp-server"
    ],
    "mcp_servers_optional": [              // warn-log if absent, skill checks at runtime to enable features
      "code-review-graph",                 // QA regression scope=impacted (fallback tests-only if absent)
      "playwright"                         // wireframe_check (skill /qa adds dynamically to check-list if qa.wireframe_check.enabled=true)
    ]
  },
  "develop": {
    "review_cycles_max": 3,                // max ping-pong review↔developer
    "auto_apply_review_feedback": true,    // dev auto-applies feedback without confirm
    "fail_strategy": "next-ticket",        // next-ticket|stop|retry — if max cycles reached without approval
    "reviews": {                           // 3 specialized reviews (parallel, static on diff)
      "technical": {
        "severity_threshold": "minor"      // info|minor|major|critical — blocks if ≥ threshold
      },
      "functional": {
        "severity_threshold": "minor"      // unmet AC = major by default
      },
      "security": {
        "severity_threshold": "info"       // strict — blocks on anything but clean
      }
    }
    // Per-type runtime disable: flags --no-tech / --no-functional / --no-security
  },
  "qa": {
    "qa_cycles_max": 2,                    // ping-pong QA↔dev (independent from /develop review cycle)
    "auto_apply_qa_feedback": true,        // dev auto-applies fixes without confirm
    "severity_threshold": "minor",         // info|minor|major|critical — blocks exit of QA Phase if ≥ threshold
    "retrigger_review": false,             // if true AND fixes applied: re-run /develop 3 reviewers on post-QA diff
    "regression": {
      "enabled": true,
      "scope": "impacted"                  // impacted (via code-review-graph MCP) | full | tests-only
    },
    "wireframe_check": {
      "enabled": false,                    // opt-in (Playwright setup required)
      "mode": "playwright",                // playwright (only mode supported for now)
      "diff_threshold_pct": 5,             // tolerated pixel diff %
      "severity_on_mismatch": "major"
    }
  },
  "lifecycle_scripts": {                   // CUSTOM lifecycle scripts (≠ Claude Code hooks)
    // ⚠️ These lifecycle_scripts are SCRIPTS SPECIFIC TO THIS WORKFLOW.
    //    They are NOT interpreted by Claude Code (not in native
    //    SessionStart/PreToolUse/etc events). They are executed explicitly by
    //    each skill via _shared/run-lifecycle-script.sh at skill lifecycle points.
    // Define only useful scripts. Absent keys = implicit skip.
    // Supported scripts: pre_define, post_define, pre_ticket, post_ticket,
    //                    pre_wireframe, post_wireframe, pre_design, post_design,
    //                    pre_develop, post_develop, pre_qa, post_qa
    // Value = path to executable script (receives context JSON on stdin).
    // Example:
    // "post_ticket": ".claude/lifecycle_scripts/notify-slack.sh"
  },
  "templates": {                           // template resolution (see ../contributing/templates.md)
    "use_repo_native": true,               // reuse .github/.gitlab templates
    "tickets": {
      "user_story": null,                  // e.g. ".claude/templates/my-user-story.md"
      "bug":         null,
      "epic":        null
    },
    "pr":                  null,           // e.g. ".claude/templates/my-pr.md"
    "review_thread":       null,           // comment posted on PR/MR (best-effort)
    "aggregated_feedback": null            // internal blob for /develop fix-loop
    // Resolution order: explicit override > repo-native > bundled.
    // use_repo_native=true (default) → /ticket and /develop reuse the host's
    //   markdown templates (.github/ISSUE_TEMPLATE/, .gitlab/
    //   issue_templates/, PULL_REQUEST_TEMPLATE.md) before falling back to bundled.
    //   Explicit overrides above always win. false → ignores repo-native
    //   templates. JIRA has no repo-native convention.
    // Overrides null by default → fallback to bundled `_shared/templates/...`.
    // Relative path → resolved from project root. Absolute → as-is.
    // Override pointing to non-existent file → resolve-template.sh exits 2.
  },
  "defaults": {
    "lang": "fr",                          // fr | en
    "auto_mode": false,
    "save_mode": true,
    "branch_mode": true,
    "economy_mode": false
  }
}
```

## Auth: ABSENT

MCP/CLI handle independently:

- `gh auth status`, `glab auth status`, `jira me`
- AFFiNE/Notion MCP servers use their own config (`$AFFINE_API_TOKEN` env, etc.)
- Skill checks auth at runtime via `_shared/detect-platforms.sh`

## Fallback rules

1. Config absent → defaults bundled in skill
2. Section absent → section defaults (except `documentation`/`tickets`/`testing` → interactive setup)
3. Field absent → default or inheritance:
   - `tickets.platform = "inherit"` → `= repository.platform`
   - `testing.*_command` absent → auto-detect via `package.json`/`pyproject.toml`/etc.
   - `repository.protected_branches` absent → `["main"]`
   - `naming.ticket_id_regex` absent → patterns per platform (JIRA: `[A-Z]+-[0-9]+`, GitHub: `#[0-9]+`)
   - `naming.feature_slug_max_length` absent → 40
   - `develop.review_cycles_max` absent → 3
   - `develop.reviews.{type}.severity_threshold` absent → `minor` (except `security` → `info`)
   - `qa.qa_cycles_max` absent → `2`
   - `qa.severity_threshold` absent → `minor`
   - `qa.retrigger_review` absent → `false`
   - `qa.regression.scope` absent → `impacted` (fallback `tests-only` if code-review-graph MCP absent)
   - `qa.wireframe_check.enabled` absent → `false` (opt-in)
4. **`feature_id` format hardcoded:** `NN-kebab` (e.g. `01-auth`). `NN` = auto-incremented number from `index.md`, `kebab` = slugified feature name truncated to `feature_slug_max_length`.
5. CLI flag override always wins (`--platform=...`, `--review-cycles=N`)
6. `ai.mcp_servers_required` validated at startup for each skill — fail fast if absent
7. `ai.mcp_servers_optional` validated at startup — log warning if absent, dependent features auto-disabled (e.g. code-review-graph absent → `qa.regression.scope` forced to `tests-only`)

## First-run auto-generation

1. `_shared/setup-config.sh` runs if `snapship.config.json` is absent
2. Parses `.git/config` → extracts remote URL → detects repo platform + URLs
3. Tries active MCP servers → proposes match (atlassian, github, notion, affine, frame0)
4. AskUserQuestion mapping for ambiguous cases + critical fields (jira.project_key if JIRA, workspace_id, root_page_id, template_ids)
5. Generates `snapship.config.json` with detected sections
6. User can edit afterwards (config = source of truth, no re-detection)

## Per-step section auto-discovery

| Skill        | Required sections                                       | If absent                      |
| ------------ | ------------------------------------------------------- | ------------------------------ |
| `/define`    | `documentation`, `ai`                                   | Interactive documentation setup |
| `/ticket`    | `tickets`, `repository`, `naming`                       | Interactive tickets setup      |
| `/wireframe` | `wireframes`, `documentation`                           | Error if `wireframes` absent   |
| `/design`    | `design`, `documentation`                               | Skill silently skipped if `design` absent (optional) |
| `/develop`   | `repository`, `tickets`, `testing`, `naming`, `develop` | Interactive setup if missing   |
| `/qa`        | `tickets`, `testing`, `qa`                              | Interactive setup if missing   |

## Wireframes + design examples

**Penpot only (low-fi wireframe + hi-fi design mockup in same file)**

```jsonc
"wireframes": {
  "platform": "penpot",
  "penpot": { "file_id": "abc-uuid", "file_name": "MyProduct — Wireframes" }
},
"design": {
  "platform": "penpot",
  "penpot": { "file_id": "abc-uuid", "design_system_page": "Components" }
}
// /design step-00 detects identical file_id → AskUserQuestion auto-link Yes
```

**Figma only (hi-fi mockups, no wireframes)**

```jsonc
"design": {
  "platform": "figma",
  "figma": {
    "file_key": "X9YZ...",
    "file_name": "MyProduct — Design",
    "token_env": "FIGMA_ACCESS_TOKEN"
  }
}
```

**Mixed (Frame0 wireframes + Figma design)**

```jsonc
"wireframes": {
  "platform": "frame0",
  "frame0": { "api_port": 58320 }
},
"design": {
  "platform": "figma",
  "figma": { "file_key": "..." }
}
// No auto-link (different platforms) — design.figma requires separate binding
```

## Secrets: `.env.snapship`

Secrets (Figma PAT, other tokens) **do not live in `snapship.config.json`**
(commit-friendly). They are read from `.env.snapship` at the project root
(gitignored by default).

**Format:** `KEY=VALUE` per line. Comments `#`. Quotes `"…"` / `'…'`
stripped automatically. No shell substitution.

```bash
# .env.snapship — gitignored, per-project secrets
FIGMA_ACCESS_TOKEN=figd_abc123def456
# OPENAI_API_KEY="sk-…"
```

**Resolution:** the `/design` (figma) and `/wireframe` (figma) skills call
`skills/_shared/load-env.sh --project-root="$PWD" --key=<NAME>` where `<NAME>`
comes from `design.figma.token_env` / `wireframes.figma.token_env` (default
`FIGMA_ACCESS_TOKEN`). Value exported in env for `figma-console-mcp`.

**Common errors:**
- File missing → skill halts with creation instructions.
- Key missing → skill halts with add instructions.
- Invalid Figma token → MCP server returns 401 (separate case).

**Generate a Figma PAT:** Figma → Settings → Personal access tokens → Generate
new token. Scope: read + edit the file.

## Custom lifecycle scripts (≠ Claude Code hooks)

`pre_<skill>` executed before step-00, `post_<skill>` after the last step. Supported scripts: `pre_define`, `post_define`, `pre_ticket`, `post_ticket`, `pre_wireframe`, `post_wireframe`, `pre_design`, `post_design`, `pre_develop`, `post_develop`, `pre_qa`, `post_qa`.

Orchestrated explicitly by each skill via `_shared/run-lifecycle-script.sh` — user shell scripts, **not** native Claude Code hooks (which operate at session/tool level: `SessionStart`, `PreToolUse`, etc.).

Skill passes JSON context via stdin (feature_id, ticket_ids, etc.).

## Runtime validation (JSON Schema)

`load-config.sh` validates config against `_shared/schemas/config.schema.json`:

- Ajv or `jq` + basic check
- Schema errors → exit 1 + field path + reason
- Non-blocking stderr warnings:
  - `tickets.platform != "jira"` + `tickets.jira.*` set → "tickets.jira section ignored on platform Y"
  - `lifecycle_scripts.<name>` set to non-existent script → "script X invalid path"

Resolution cache in `.snap/.config-resolved.json` (invalidated if mtime changes).
