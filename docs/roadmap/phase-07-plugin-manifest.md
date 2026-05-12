# Phase 7 — Plugin manifest finalization

**Objectif:** `.claude-plugin/plugin.json` conforme schema officiel CC, validé localement, installable via marketplace locale.

> Décisions clés (vérifiées via docs CC `code.claude.com/docs/en/plugins-reference.md`):
>
> - **Seul `name` est requis** dans le manifest. Tout le reste (`version`, `description`, `author`, `license`, `keywords`, etc.) est metadata optionnel mais recommandé.
> - **Pas de champs custom paths** (`skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path` — invalides). Schéma CC: `skills`, `commands`, `agents`, `hooks`, `mcpServers`, `outputStyles`, `lspServers`. Auto-discovery depuis dossiers conventionnels (`skills/`, `commands/`, `agents/`, `hooks/`) — déclarations explicites uniquement si paths non-standards.
> - **`commands` n'est pas un array d'objets** `{name, description}`. C'est un string|array de **paths** (vers `.md` files ou directory). Description vit dans le frontmatter du `.md`. Nos slash commands sont des **skills** (`/define`, `/ticket`, etc.), auto-découverts depuis `skills/` — donc le champ `commands` ne sera pas utilisé.
> - **`mcp_servers` (snake_case)** n'existe pas. Schéma CC: `mcpServers` (camelCase) inline OU fichier `.mcp.json` séparé à racine plugin. On utilise `.mcp.json` (déjà fait Phase 7.4 amorce).

## 7.1 Migration manifest

- [x] Créer `.claude-plugin/plugin.json` (clean, schema-conforme)
- [x] `trash` ancien `plugin.json` racine (legacy, source de confusion)
- [x] Champs retenus: `name`, `version` (semver), `description`, `author{name,email}`, `homepage`, `repository`, `license`, `keywords`
- [x] Champs supprimés (custom invalides): `skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path`, `commands` (objet), `mcp_servers`

## 7.2 Components

- [x] Skills: auto-discovery `skills/` (rien à déclarer)
- [x] Agents: auto-discovery `agents/` (rien à déclarer)
- [x] MCP: `.mcp.json` racine plugin (déjà fait — code-review-graph bundlé)
- [x] Hooks: pas de `hooks/hooks.json` pour v0.1.0 (à reconsidérer si besoin lifecycle plugin)

## 7.3 Validation + test install

- [x] `claude plugin validate .` passe sans warning (plugin + marketplace)
- [x] `.claude-plugin/marketplace.json` brouillon créé (name `snapship-local`, source `./`)
- [x] `/plugin validate .` passe sans warning (in-session, manuel)
- [x] Test install local: `/plugin marketplace add ./` puis `/plugin install snap@snapship-local`
- [x] Vérifier 6 skills disponibles dans session (`init`, `define`, `ticket`, `wireframe`, `develop`, `qa`) + 4 agents listables

## 7.4 Distribution metadata

- [x] `CHANGELOG.md` (Keep-a-Changelog, semver)
- [x] `NOTICE` (attributions community MCPs: code-review-graph, affine-mcp-server, frame0-mcp-server, playwright-mcp)
- [x] Sync `docs/plugin.md` + `docs/structure.md` + `docs/decisions.md` + `docs/README.md` avec nouveau path `.claude-plugin/plugin.json`

**Sortie:** plugin valide schema CC, installable localement, prêt marketplace.
