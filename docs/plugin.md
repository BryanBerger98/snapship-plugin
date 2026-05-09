# Plugin

## Distribution

Plugin v1 packagé via `plugin.json` à la racine repo. Bundle officiel Claude Code:

- Install marketplace CC (URL repo plugin)
- Ou clone manuel + symlink/copy vers `~/.claude/skills/` + `~/.claude/agents/`
- Compatible installation projet (`.claude/skills/`)

**Pas de convention symlink custom `~/.agents/`.** Paths officiels CC uniquement.

## Manifest `plugin.json`

```jsonc
{
  "name": "artysan",
  "version": "1.0.0",
  "description": "Product workflow: define → ticket → wireframe → develop → qa",
  "skills_path": "skills/",
  "skills": ["define", "ticket", "wireframe", "develop", "qa"],
  "agents_path": "agents/",
  "agents": [
    "code-reviewer-technical", "code-reviewer-functional",
    "code-reviewer-security", "code-reviewer-qa"
  ],
  "shared_scripts_path": "skills/_shared/",
  "schemas_path": "skills/_shared/schemas/",
  "templates_path": "skills/_shared/templates/",
  "mcp_servers_recommended": ["affine-mcp-server", "frame0-mcp-server", "code-review-graph", "playwright"]
}
```

## Layout repo plugin

```
artysan/  (plugin repo)
├── plugin.json                    # manifest CC
├── skills/                        # → ~/.claude/skills/ ou .claude/skills/
│   ├── define/
│   ├── ticket/
│   ├── wireframe/
│   ├── develop/
│   ├── qa/
│   └── _shared/                   # scripts + templates + schemas partagés
└── agents/                        # → ~/.claude/agents/ ou .claude/agents/
    ├── code-reviewer-technical.md
    ├── code-reviewer-functional.md
    ├── code-reviewer-security.md
    └── code-reviewer-qa.md
```

Détails arbre complet: [structure.md](structure.md).

## Install

### Marketplace CC

```bash
claude plugin install artysan
```

### Manuel (dev / preview)

```bash
git clone https://github.com/<org>/artysan.git ~/projects/artysan
ln -s ~/projects/artysan/skills ~/.claude/skills/artysan
ln -s ~/projects/artysan/agents ~/.claude/agents/artysan
```

### Projet-scoped

```bash
cp -r artysan/skills .claude/skills/
cp -r artysan/agents .claude/agents/
```

## MCP servers recommandés

Plugin déclare MCPs recommandés. User installe séparément (CC plugin n'embarque pas MCP servers).

| MCP                 | Rôle                                             | Required par                                        |
| ------------------- | ------------------------------------------------ | --------------------------------------------------- |
| `affine-mcp-server` | Docs primaire (PRD global + feature + galleries) | `/define`, `/wireframe`, `/ticket` (read PRD)       |
| `frame0-mcp-server` | Wireframes shapes/pages/export                   | `/wireframe`                                        |
| `code-review-graph` | Impact radius QA scope=impacted                  | `/qa` (optional, fallback `tests-only`)             |
| `playwright`        | DOM scrape wireframe diff                        | `/qa` (optional, si `wireframe_check.enabled=true`) |

Install instructions: voir [mcp-refs.md](mcp-refs.md).

## Versioning

Manifest `version` = SemVer. Compat config:

- Minor bump → backward compatible
- Major bump → instructions migration via `load-config.sh` (check `version` champ config user)

Schemas JSON validés runtime (voir [config.md](config.md) section validation).

## Skills/agents location

Plugin v1 packagé via `plugin.json`. Install marketplace CC ou clone manuel → paths officiels `~/.claude/skills/` + `~/.claude/agents/` (ou projet `.claude/`). Pas de symlink custom.

## Templates docs-defaults

Bundlés dans `skills/_shared/templates/docs-defaults/` (push opt-in via setup-config.sh premier run).

Voir [templates.md](templates.md).
