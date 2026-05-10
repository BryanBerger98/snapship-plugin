# Plugin

## Distribution

Plugin v1 packagé conforme schéma Claude Code: manifest `.claude-plugin/plugin.json`, MCP servers via `.mcp.json` racine, skills/agents auto-découverts depuis dossiers conventionnels.

- Install marketplace `bryanberger` (Phase 10): `/plugin marketplace add bryanberger/claude-plugins` puis `/plugin install snap@bryanberger`
- Ou clone manuel: `git clone … ~/.claude/plugins/snap` (auto-loaded)
- Compatible installation projet via `.claude/settings.json` (`extraKnownMarketplaces` + `enabledPlugins`)

**Pas de symlink custom.** Paths officiels CC uniquement.

## Manifest `.claude-plugin/plugin.json`

```json
{
  "name": "snap",
  "version": "0.1.0",
  "description": "Workflow produit Claude Code: 5 skills enchaînables (define → ticket → wireframe → develop → qa).",
  "author": { "name": "Bryan Berger", "email": "contact@bryanberger.dev" },
  "homepage": "https://github.com/BryanBerger98/snapship-plugin",
  "repository": { "type": "git", "url": "https://github.com/BryanBerger98/snapship-plugin" },
  "license": "MIT",
  "keywords": ["workflow", "product-management", "tickets", "wireframes", "code-review", "qa", "affine", "frame0"]
}
```

> **Seul `name` est requis** par le schéma CC. Les autres champs sont metadata recommandée.

### Champs **non utilisés** (et pourquoi)

| Champ | Statut | Raison |
|-------|--------|--------|
| `skills` | absent | Auto-discovery `skills/` racine plugin |
| `agents` | absent | Auto-discovery `agents/` racine plugin |
| `commands` | absent | Nos slash commands sont des **skills**, pas des `commands/*.md` |
| `hooks` | absent | Pas de lifecycle plugin pour v0.1.0 |
| `mcpServers` | absent inline | Déclarés via `.mcp.json` séparé (équivalent fonctionnel) |
| `outputStyles` / `lspServers` | absent | Non pertinents |

> **Champs custom anciennement présents et supprimés** (invalides — pas dans schéma CC): `skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path`, `mcp_servers` (snake_case).

## Layout repo plugin

```
snapship-plugin/
├── .claude-plugin/
│   └── plugin.json                # manifest CC (name, version, metadata)
├── .mcp.json                      # MCP servers bundlés (code-review-graph)
├── CHANGELOG.md                   # Keep-a-Changelog
├── NOTICE                         # attributions community MCPs
├── LICENSE                        # MIT
├── README.md
├── skills/                        # auto-découvert
│   ├── define/
│   ├── ticket/
│   ├── wireframe/
│   ├── develop/
│   ├── qa/
│   └── _shared/                   # scripts + templates + schemas partagés (utilisés par skills, pas un dossier CC standard)
├── agents/                        # auto-découvert
│   ├── code-reviewer-technical.md
│   ├── code-reviewer-functional.md
│   ├── code-reviewer-security.md
│   ├── code-reviewer-qa.md
│   └── developer.md
└── docs/                          # specs internes (pas distribuées run-time)
```

Détails arbre complet: [structure.md](structure.md).

## Validation

```bash
claude plugin validate .          # ou /plugin validate . in-session
```

CI run cette validation à chaque push (Phase 7.3).

## Install

### Marketplace `bryanberger` (Phase 10)

```bash
/plugin marketplace add bryanberger/claude-plugins
/plugin install snap@bryanberger
```

### Clone manuel global

```bash
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap
```

Plugin auto-chargé au prochain démarrage Claude Code.

### Projet-scoped (équipe)

`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "bryanberger": { "source": { "source": "github", "repo": "bryanberger/claude-plugins" } }
  },
  "enabledPlugins": { "snap@bryanberger": true }
}
```

## MCP servers

| MCP                 | Bundling     | Rôle                                             | Required par                                  |
| ------------------- | ------------ | ------------------------------------------------ | --------------------------------------------- |
| `code-review-graph` | **bundled**  | Knowledge graph (impact, flows, tests)           | `/develop` (warm-up), `/qa` (scope=impacted)  |
| `affine-mcp-server` | required     | Docs primaire (PRD + features + galleries)      | `/define`, `/wireframe`, `/ticket`            |
| `frame0-mcp-server` | optional     | Wireframes shapes/pages/export                   | `/wireframe`                                  |
| `playwright`        | optional     | Headless browser screenshot                      | `/qa` si `wireframe_check.enabled=true`       |

`code-review-graph` est déclaré dans `.mcp.json` (auto-start). Binaire installé séparément: `pipx install code-review-graph`. Voir [mcp-refs.md](mcp-refs.md) pour autres MCPs.

## Versioning

Manifest `version` = SemVer. Compat config:

- Minor bump → backward compatible
- Major bump → instructions migration via `load-config.sh` (check `version` champ config user)

Schemas JSON validés runtime (voir [config.md](config.md) section validation).

## Templates docs-defaults

Bundlés dans `skills/_shared/templates/docs-defaults/` (push opt-in via setup-config.sh premier run). Voir [templates.md](templates.md).
