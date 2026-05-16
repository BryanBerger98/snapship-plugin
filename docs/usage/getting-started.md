# Getting started — first feature in 5 minutes

Prerequisites: plugin installed ([install.md](install.md)) and `claude` launched
from the root of a Git repo.

## 1. `/snap:init` — bootstrap workspace

Run **once per project**:

```text
/snap:init
```

Snap probes the environment (`.git/config`, active MCPs, `package.json`,
`pyproject.toml`…) and suggests defaults via `AskUserQuestion`. Typical answers:

| Question     | Example answer                               |
| ------------ | -------------------------------------------- |
| Repo         | `github` (detected from `.git/config`)       |
| Tickets      | `linear`                                     |
| Docs         | `notion`                                     |
| Wireframes   | `frame0`                                     |
| Design       | `figma` (optional)                           |
| Lang         | `fr`                                         |

Autonomous mode — uses all detected defaults:

```text
/snap:init --auto
```

On exit:

```
<project>/
  snap.config.json     # ← committable, shared with team
  .snap/                   # ← local workspace
    manifests/             # ← committed (platform references)
    tickets/               # ← committed (ticket cache)
    PRDs/ designs/ wireframes/ queues/   # ← gitignored (staging)
    progress.json          # ← gitignored (runtime state)
```

> Re-init later: `/snap:init --force` (rewrites `snap.config.json`,
> **preserves** `.snap/`).

## 2. `/snap:define` — first feature

```text
/snap:define "Email + magic link authentication"
```

Pipeline:

1. **step-00** creates the `feature_id` (e.g. `01-auth-email`) and slug.
2. **step-01..03** interactive PRD brainstorm: goal, scope, screens,
   acceptance criteria. Answers via `AskUserQuestion`.
3. **step-04** writes `.snap/PRDs/01-auth-email.md` + pushes to the configured
   docs platform (Notion/AFFiNE). The remote page becomes the source of
   truth; local serves as staging.
4. **step-05** creates `.snap/manifests/01-auth-email.manifest.json` with
   `state: defined` and `refs.prd_page = { platform, page_id, url, synced_at }`.

Resumable at any point: `/snap:define --resume` (or `-r`).

## 3. `/snap:ticket` — break down into tickets

```text
/snap:ticket 01-auth-email
```

Reads the PRD, proposes a breakdown into conventional-commit-typed tickets
(`feat`, `fix`, `chore`…), asks for confirmation, writes
`.snap/tickets/01-auth-email.json`, then pushes to the configured tickets
platform (GitHub Issues, GitLab, JIRA, Linear). Each ticket gets a
`platform_id` (`#42`, `PROJ-123`…) and a `url`.

Repo-native templates: if your repo exposes `.github/ISSUE_TEMPLATE/*.md` or
`.gitlab/issue_templates/*.md`, snap detects them and fills them
section-by-section instead of writing the bundled template. See
[templates.md](../contributing/templates.md).

## 4. (optional) `/snap:wireframe` then `/snap:design`

If the feature has at least one UI ticket:

```text
/snap:wireframe                 # low-fi via Frame0/Penpot/Figma
/snap:design 01-auth-email      # hi-fi via Penpot/Figma
```

Each skill generates the assets, pushes to the platform, and back-links
`wireframe_url` + `design_url` in `tickets/{feature_id}.json`.

## 5. `/snap:develop` — implement ticket by ticket

```text
/snap:develop 01-auth-email          # batch all tickets of the feature
# or
/snap:develop t-001                  # one specific ticket (local_id or platform_id)
```

**Standalone** or **session** loop:

- standalone: one ticket → one atomic commit → continue.
- session: chains all open tickets of a feature through to the PR.

Three automatic reviewers (technical / functional / security) run
post-commit; a draft PR is opened with the summary.

## 6. `/snap:qa` — runtime validation

```text
/snap:qa 01-auth-email
```

Runs regression-scope tests (via `code-review-graph` impact radius if
available), then a Playwright visual diff against the wireframes/mockups
referenced in the tickets. Critical failure → reopens the affected tickets
as `qa_blocked`.

## Full cycle

```text
/snap:init                           # 1× per project
/snap:define "..."                   # 1× per feature
/snap:ticket   <feature_id>
/snap:wireframe                      # if UI
/snap:design   <feature_id>          # if hi-fi UI
/snap:develop  <feature_id>
/snap:qa       <feature_id>
/snap:doc-update <feature_id>        # post-ship — refreshes the functional doc
```

See [workflow.md](workflow.md) for platform details and
[skills/](skills/) for each skill (flags, pipeline, outputs).

## If something breaks

[troubleshooting.md](troubleshooting.md) — MCP auth, resume conflicts,
secrets, sync fail.
