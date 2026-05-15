# Troubleshooting

Catalog of common errors — symptom → cause → fix. If a case is missing,
open an issue at [github.com/BryanBerger98/snapship-plugin](https://github.com/BryanBerger98/snapship-plugin/issues).

## Installation & runtime

### `snap` doesn't show up in `/plugin list`

- Check the path: `ls ~/.claude/plugins/snap/.claude-plugin/plugin.json`.
- Restart Claude Code (plugins are scanned at startup).
- If project-scoped: `ls .claude/plugins/snap/.claude-plugin/plugin.json`
  from the repo root.

### `ERROR: jq required` when running a skill

`jq` is required for all `_shared/` helpers. Install:

```bash
brew install jq          # macOS
apt-get install -y jq    # Debian/Ubuntu
```

### `code-review-graph: command not found`

The binary is declared in the plugin's `.mcp.json` but is **not
auto-installed**.

```bash
pipx install code-review-graph
```

Without it, `/snap:develop` and `/snap:qa` degrade: no impact radius,
`qa.regression.scope` forced to `tests-only`. Acceptable but suboptimal.

## `/snap:init`

### `ERROR: snapship.config.json already exists`

```text
/snap:init --force
```

The content of `.snap/` is **preserved** — only the config file is
rewritten. If you truly want to start from scratch:

```bash
trash .snap snapship.config.json
```

(and **never** `rm -rf` — use `trash` to keep it reversible.)

### `--auto` mode fails: "required field unresolved"

`--auto` requires every required field to be deducible. If no docs MCP is
detected, `documentation.platform` stays empty and init stops.
Solution:

```text
/snap:init             # interactive mode, choose `none` or install the MCP
```

## Secrets — `.env.snapship`

### `ERROR: .env.snapship not found`

The file must exist at the **project root** (not in `.snap/`).

```bash
touch .env.snapship
chmod 600 .env.snapship
echo "FIGMA_ACCESS_TOKEN=figd_..." >> .env.snapship
```

### `key 'FIGMA_ACCESS_TOKEN' not found in .env.snapship`

Strict `KEY=VALUE` format, **no whitespace** around `=`, no shell
expansion.

```dotenv
FIGMA_ACCESS_TOKEN=figd_xxxxxxxx     # OK
FIGMA_ACCESS_TOKEN =figd_xxxxxxxx    # KO
FIGMA_ACCESS_TOKEN="$HOME/secret"    # KO — no expansion
```

Override the key name via `wireframes.figma.token_env` / `design.figma.token_env`.

## MCP servers

### MCP timeout / `unreachable`

```bash
claude mcp list
```

- If the server doesn't appear → install + restart Claude Code.
- If it appears but doesn't respond → check the token in the MCP config
  (env variable exposed to the server, **not** in `.env.snapship` —
  `.env.snapship` is read by snap directly, not by the MCPs).
- For AFFiNE / Notion: test the API outside Claude Code with `curl` to
  isolate a scope / token expiration issue.

### Figma Desktop Bridge plugin doesn't respond

`/snap:wireframe figma` and `/snap:design figma` require **Figma Desktop
running** and the `figma-console-mcp` plugin active in the targeted file.

Checklist:
1. Figma Desktop open (not the web).
2. Bridge plugin launched via `Plugins → Development → figma-console-mcp`.
3. `wireframes.figma.file_key` (or `design.figma.file_key`) matches the
   `fileKey` of the active file. Otherwise step-00 halts.

## Resume & progress

### `/snap:* --resume` restarts at an unexpected step

`progress.sh resume next --skill=<name>` reads `.snap/progress.json`
`in_flight[]`. If several features are in progress in parallel, add
`--feature-id=` explicitly.

Inspect the state:

```bash
jq '.in_flight, .steps' .snap/progress.json
```

Restart from scratch on a feature:

```bash
jq 'del(.in_flight[] | select(.feature_id == "01-auth-email"))' \
   .snap/progress.json > .snap/progress.tmp && mv .snap/progress.tmp .snap/progress.json
```

### Partial-match feature_id returns multiple candidates

Since v1.0.0, partial-match is **no longer** in the helper (`progress.sh
resume` requires an exact id). It's each skill's `step-00-init.md` that
performs matching. Typical error:

```
Multiple features match 'auth': 01-auth-email, 02-auth-sso. Be more specific.
```

→ use the full `feature_id`.

## Platform sync

### `sync-push` fails: `Platform error 429 / throttle`

Retry later, or on the platform side increase quota / API key scope.
`sync-push.sh` is idempotent (write-through outbox + ack), a retry does
not duplicate the resource.

### `manifest.refs.{X}.sync_status` stays `pending`

Inspect:

```bash
jq '.refs' .snap/manifests/<feature_id>.manifest.json
```

`pending` = not yet pushed (offline first run, or silent failure).
Replay:

```text
/snap:fetch <feature_id>       # re-sync from remote (read)
```

For forced repush: re-run the skill that produced the ref
(`/snap:define --resume` repushes the PRD, etc.).

## Version mismatch & migration

### `MAJOR version mismatch detected`

The plugin was updated (`git pull` on `~/.claude/plugins/snap`) but the
local workspace is on an earlier schema.

```text
/snap:upgrade --dry-run        # preview the plan
/snap:upgrade                  # apply (auto backup .snap.bak-v{x}-{ts}/)
```

### v0.6 workspace (legacy `.claude/product/`)

```text
/snap:upgrade --from=0.6.0
```

See [migration-v1.md](migration-v1.md) for detailed transformations.

## Tests & QA

### `/snap:qa` repeated flaky verdicts

Typical cause: non-deterministic test order or shared state. `/snap:qa`
tracks `qa_last_flaky_verdict` in the ticket. If `flaky` 2× in a row,
escalate: open a dedicated `test-flakiness` ticket rather than retrying.

### Playwright wireframe diff always fails

- Check that the ticket has `wireframe_url` (or `design_url`) — otherwise
  the diff has no reference.
- `qa.wireframe_check.tolerance` (config): too strict a value? Reasonable
  default is around 0.05.
- MCP `playwright-mcp` active? `claude mcp list`.

## Where to look next

| Symptom                                | Doc                                                |
| -------------------------------------- | -------------------------------------------------- |
| Understand the config                  | [configuration.md](configuration.md)               |
| Understand the global flow             | [workflow.md](workflow.md)                         |
| Understand the `.snap/` structure      | [structure.md](../contributing/structure.md)       |
| Understand a specific skill            | [skills/](skills/)                                 |
| MCP refs (Frame0, AFFiNE, Playwright…) | [mcp-refs.md](mcp-refs.md)                         |
