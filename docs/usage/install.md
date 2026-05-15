# Installation

Snap est un **plugin Claude Code**. Trois voies d'installation, par ordre de
préférence :

1. **Marketplace** `bryanberger` (recommandé — repo [`BryanBerger98/claude-plugins`](https://github.com/BryanBerger98/claude-plugins)).
2. **Clone manuel global** dans `~/.claude/plugins/` (alternative sans marketplace).
3. **Clone projet-scoped** dans `<project>/.claude/plugins/` (isole une version
   par projet).

> Le plugin n'a **aucun installer automatique** des MCP/CLI externes. Tout ce
> qui est runtime obligatoire (jq, `code-review-graph`, MCPs docs/design) doit
> exister avant le premier `/snap:init`.

## 1. Marketplace (recommandé)

```text
/plugin marketplace add BryanBerger98/claude-plugins
/plugin install snap@bryanberger
```

Update via `/plugin update snap@bryanberger`, désinstall via
`/plugin remove snap`. La marketplace track le tag git de la release (`v1.0.0`
actuellement) — à chaque nouvelle release du plugin, la marketplace est
bumpée et `/plugin update` rapatrie la nouvelle version.

## 2. Clone manuel global

Snap est auto-loadé par Claude Code quand il est présent dans
`~/.claude/plugins/`. Aucune configuration globale requise.

```bash
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap
```

Relance Claude Code. Les commandes `/snap:*` apparaissent dans la palette.

Pour update :

```bash
cd ~/.claude/plugins/snap && git pull
```

Si le tag local et le tag distant divergent en **MAJOR**, lance
`/snap:upgrade` au premier coup de skill suivant — il détecte le mismatch et
migre `.snap/` du projet.

## 3. Clone projet-scoped

Quand tu veux **épingler une version** à un repo précis (équipe, CI repro) :

```bash
cd <project>
git clone https://github.com/BryanBerger98/snapship-plugin .claude/plugins/snap
echo ".claude/plugins/" >> .gitignore       # ou commit volontairement
```

Le plugin local **gagne** sur la version globale. Utile pour figer v1.0.0
pendant qu'on teste v1.1.0 globalement.

## Prérequis runtime

### Obligatoires

| Composant                | Vérifier                      | Install                                      |
| ------------------------ | ----------------------------- | -------------------------------------------- |
| Claude Code CLI          | `claude --version`            | https://claude.com/code                      |
| `jq`                     | `jq --version`                | `brew install jq` / `apt install jq`         |
| `code-review-graph`      | `code-review-graph --help`    | `pipx install code-review-graph`             |
| MCP docs (un parmi)      | `claude mcp list`             | `affine-mcp-server` ou `notion-mcp-server`   |
| MCP design ou wireframe  | `claude mcp list`             | un parmi `figma`, `penpot`, `frame0`         |

`code-review-graph` est déclaré dans `.mcp.json` bundlé — Claude Code lance
le serveur, **il ne l'installe pas**. Si le binaire est absent, `/snap:develop`
et `/snap:qa` tournent en mode dégradé (`qa.regression.scope=tests-only`,
plus d'impact radius).

### Optionnels

| Composant            | À quoi ça sert                                          |
| -------------------- | ------------------------------------------------------- |
| MCP `playwright`     | `/snap:qa` wireframe diff visuel                        |
| CLI `gh` / `glab`    | Fallback si MCP tickets GitHub/GitLab absent            |
| CLI `jira`           | Fallback tickets JIRA                                   |

## Secrets — `.env.snapship`

Snap lit les secrets **uniquement** depuis `<project>/.env.snapship`. Ce
fichier est gitignored par défaut.

```dotenv
# .env.snapship — racine projet
FIGMA_ACCESS_TOKEN=figd_xxxxxxxxxxxxxxxxxxxx
# AFFINE_API_TOKEN et NOTION_TOKEN sont lus par les MCP servers eux-mêmes,
# pas par snap directement.
```

Helper de lecture : `skills/_shared/load-env.sh --project-root=$PWD --key=FIGMA_ACCESS_TOKEN`.

| Clé                   | Quand                                                 |
| --------------------- | ----------------------------------------------------- |
| `FIGMA_ACCESS_TOKEN`  | `wireframes.platform=figma` ou `design.platform=figma`|

Override de la clé via `wireframes.figma.token_env` / `design.figma.token_env`
dans `snapship.config.json` (ex. `FIGMA_DEV_TOKEN`).

## Vérification

```bash
cd <project>
claude
```

Dans la session :

```text
/snap:init --dry-run        # (pas encore implémenté — utiliser /snap:init et abort)
/plugin list                 # snap@1.0.0 doit apparaître
```

Si `/snap:*` n'apparaît pas : redémarre Claude Code, vérifie le chemin
d'install, vérifie `~/.claude/plugins/snap/.claude-plugin/plugin.json`.

## Étape suivante

[getting-started.md](getting-started.md) — premier `/snap:init` puis première
feature avec `/snap:define`.
