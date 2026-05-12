# Phase 11 — Install user-side (3 méthodes)

## 11.1 Marketplace `bryanberger` (recommandé)

```bash
# Dans Claude Code session
/plugin marketplace add bryanberger/claude-plugins
/plugin install snap@bryanberger
# Skills + agents + scripts + schemas + templates copiés ~/.claude/
```

Auto-update opt-in via `/plugin` → onglet Marketplaces.

## 11.2 Clone manuel global

```bash
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap
# Plugin auto-loaded au prochain démarrage CC
```

## 11.3 Projet-scoped (équipe)

```bash
# Dans repo projet, ajouter à .claude/settings.json:
{
  "extraKnownMarketplaces": {
    "bryanberger": { "source": { "source": "github", "repo": "bryanberger/claude-plugins" } }
  },
  "enabledPlugins": { "snap@bryanberger": true }
}
# Membres équipe: prompt install au prochain démarrage CC dans le projet
```

## 11.4 Setup premier projet

```bash
cd <mon-projet>
claude
# Dans session:
/define "feature description"
# → setup-config.sh interactive wizard détecte:
#   - .git/config (platform, url)
#   - MCP servers actifs (affine, frame0, etc.)
#   - test commands (package.json, Cargo.toml, etc.)
# → écrit snapship.config.json racine projet
# → continue step-01-discover ou green-field
```

**Sortie:** user productif < 10 min après install.
