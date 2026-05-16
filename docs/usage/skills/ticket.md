# `/snap:ticket` — feature → tickets

Breaks a feature PRD into atomic, dev-ready tickets, enriches each one via
parallel research agents, formats them per platform, and pushes them to
GitHub / GitLab / JIRA.

## What it does

Turns a feature PRD into a numbered list of stories ready for
`/snap:develop` — each ticket is 5 to 30 minutes of work and touches 1 to 5
files.

## When to use it

- A `prd-feature.md` exists under `.snap/manifests/{feature_id}/`.
- You want dev-ready stories on the configured ticket platform.
- To resume after an interruption (`--resume`).

## Prerequisites

`/snap:init` and `/snap:define` run. A resolved ticket platform
(MCP first, otherwise the `gh` / `glab` / `jira` CLI).

## Syntax

```
/snap:ticket [--resume|-r] [--feature=NN-slug] [--platform=github|gitlab|jira]
             [--max-stories=N] [--dry-run]
```

## Flags

| Flag                          | Effect                                                                                 |
| ----------------------------- | -------------------------------------------------------------------------------------- |
| `--resume` / `-r`             | Resumes at the last successful step in the feature's `progress.json` (partial-match on `feature_id`). |
| `--feature=NN-slug`           | Targets the `feature_id` (required if multiple features are defined).                  |
| `--platform=github\|gitlab\|jira` | Forces the platform, overrides `config.tickets.platform`.                          |
| `--max-stories=N`             | Caps the automatic breakdown (default: 12).                                            |
| `--dry-run`                   | Formats and logs but does not write to the platform.                                   |

## Pipeline

| #  | Step                   | Role                                                              |
| -- | ---------------------- | ----------------------------------------------------------------- |
| 00 | `step-00-init.md`      | Parses args, resolves the `feature_id`, loads the PRD + config.   |
| 01 | `step-01-load.md`      | Reads `prd-feature.md`, extracts acceptance criteria + scope.     |
| 02 | `step-02-decompose.md` | Splits the feature into atomic stories (5-30 min, 1-5 files).     |
| 03 | `step-03-enrich.md`    | Parallel agents: codebase / docs / web search per story.          |
| 04 | `step-04-format.md`    | Renders each story via the resolved template (config override > repo-native `.github`/`.gitlab` > bundled). |
| 05 | `step-05-push.md`      | Pushes via `tickets-adapter.sh` (MCP > CLI).                      |
| 06 | `step-06-index.md`     | Caches `tickets.json` + updates the feature's `manifest.json`.    |

## Outputs

- `.snap/manifests/{feature_id}/tickets.json` — cached ticket array
  (id, title, body, labels, status, platform_url). Validated against
  `_shared/schemas/tickets.schema.json`.
- `.snap/manifests/{feature_id}.manifest.json` — `tickets_count` updated.
- Tickets created on GitHub / GitLab / JIRA (URLs cached above).
- `.snap/manifests/{feature_id}/progress.json` — run journal.

## GitHub native routing (v1.1+)

When `tickets.platform = "github"` and the repo has an org-level Issue Types
feature and / or an attached Projects v2 board, story attributes are routed
**natively** instead of being inlined as labels :

| Story attribute    | Native target                       | Fallback                 |
|--------------------|-------------------------------------|--------------------------|
| `type`             | Org Issue Type (Feature / Bug / …)  | `type:<value>` label     |
| `priority`         | Projects v2 single-select field     | `priority:<value>` label |
| `estimated_size`   | Projects v2 single-select field     | `size:<value>` label     |
| `scope`            | Projects v2 single-select field     | `scope:<value>` label    |

The mapping lives in `snap.config.json` under `tickets.github` :

```jsonc
{
  "tickets": {
    "platform": "github",
    "github": {
      "enabled": true,
      "issue_types": { "user-story": "Feature", "bug": "Bug", "epic": "Epic" },
      "project": {
        "id": "PVT_kwHO...",
        "number": 12,
        "url": "https://github.com/orgs/acme/projects/12",
        "title": "Roadmap",
        "fields": {
          "priority": { "field_id": "PVTSSF_...", "values": { "must": { "option_id": "...", "option_name": "P0" } } },
          "size":     { "field_id": "PVTSSF_...", "values": { "S":    { "option_id": "...", "option_name": "S"  } } },
          "scope":    { "field_id": "PVTSSF_...", "values": { "backend": { "option_id": "...", "option_name": "Backend" } } }
        }
      },
      "label_fallback_prefixes": ["feature:"]
    }
  }
}
```

How the block gets populated:

- **Fresh install (v1.1+)** — `/snap:init` proposes detection + mapping.
- **Existing v1.0 install** — `/snap:upgrade` runs the
  `v1.0.0_to_v1.1.0` migration which detects org Issue Types + Projects v2,
  proposes a heuristic mapping, and writes the block.
- **Skipped detection** — re-run `/snap:upgrade` or delete the
  `tickets.github` key to retrigger the prompt on the next `/snap:ticket`.

Set `tickets.github.enabled = false` to permanently fall back to label-only
behaviour (v1.0 compatible).

## Next step

`/snap:wireframe` or `/snap:design` if the feature has UI, otherwise straight to
`/snap:develop`.
