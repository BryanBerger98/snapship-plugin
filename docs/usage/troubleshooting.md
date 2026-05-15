# Troubleshooting

Catalogue d'erreurs courantes — symptôme → cause → fix. Si un cas manque,
ouvre une issue sur [github.com/BryanBerger98/snapship-plugin](https://github.com/BryanBerger98/snapship-plugin/issues).

## Installation & runtime

### `snap` n'apparaît pas dans `/plugin list`

- Vérifie le chemin : `ls ~/.claude/plugins/snap/.claude-plugin/plugin.json`.
- Redémarre Claude Code (les plugins sont scannés au démarrage).
- Si projet-scoped : `ls .claude/plugins/snap/.claude-plugin/plugin.json`
  depuis la racine du repo.

### `ERROR: jq required` au lancement d'un skill

`jq` est obligatoire pour tous les helpers `_shared/`. Install :

```bash
brew install jq          # macOS
apt-get install -y jq    # Debian/Ubuntu
```

### `code-review-graph: command not found`

Le binaire est déclaré dans `.mcp.json` du plugin mais **n'est pas
auto-installé**.

```bash
pipx install code-review-graph
```

Sans lui, `/snap:develop` et `/snap:qa` dégradent : pas d'impact radius,
`qa.regression.scope` forcé à `tests-only`. Acceptable mais sous-optimal.

## `/snap:init`

### `ERROR: snapship.config.json already exists`

```text
/snap:init --force
```

Le contenu de `.snap/` est **préservé** — seul le fichier de config est
réécrit. Si tu veux vraiment repartir de zéro :

```bash
trash .snap snapship.config.json
```

(et **jamais** `rm -rf` — utiliser `trash` pour rester réversible.)

### Mode `--auto` échoue : « champ requis non résolu »

`--auto` exige que chaque champ obligatoire soit déductible. Si aucun MCP
docs n'est détecté, `documentation.platform` reste vide et l'init s'arrête.
Solution :

```text
/snap:init             # mode interactif, choisis `none` ou install le MCP
```

## Secrets — `.env.snapship`

### `ERROR: .env.snapship not found`

Le fichier doit exister à la **racine du projet** (pas dans `.snap/`).

```bash
touch .env.snapship
chmod 600 .env.snapship
echo "FIGMA_ACCESS_TOKEN=figd_..." >> .env.snapship
```

### `key 'FIGMA_ACCESS_TOKEN' not found in .env.snapship`

Format strict `KEY=VALUE`, **aucun espace** autour du `=`, pas d'expansion
shell.

```dotenv
FIGMA_ACCESS_TOKEN=figd_xxxxxxxx     # OK
FIGMA_ACCESS_TOKEN =figd_xxxxxxxx    # KO
FIGMA_ACCESS_TOKEN="$HOME/secret"    # KO — pas d'expansion
```

Override de nom de clé via `wireframes.figma.token_env` / `design.figma.token_env`.

## MCP servers

### MCP timeout / `unreachable`

```bash
claude mcp list
```

- Si le serveur n'apparaît pas → install + redémarre Claude Code.
- Si il apparaît mais répond pas → vérifier le token dans la conf MCP
  (variable d'env exposée au serveur, **pas** dans `.env.snapship` —
  `.env.snapship` est lu par snap directement, pas par les MCP).
- Pour AFFiNE / Notion : tester l'API hors Claude Code avec `curl` pour
  isoler un souci de scope / expiration token.

### Figma plugin Desktop Bridge ne répond pas

`/snap:wireframe figma` et `/snap:design figma` requièrent **Figma Desktop
lancé** et le plugin `figma-console-mcp` actif dans le file ciblé.

Checklist :
1. Figma Desktop ouvert (pas le web).
2. Plugin Bridge lancé via `Plugins → Development → figma-console-mcp`.
3. `wireframes.figma.file_key` (ou `design.figma.file_key`) correspond au
   `fileKey` du file actif. Sinon step-00 halt.

## Resume & progress

### `/snap:* --resume` repart à un step inattendu

`progress.sh resume next --skill=<name>` lit `.snap/progress.json`
`in_flight[]`. Si plusieurs features sont en cours en parallèle, ajoute
`--feature-id=` explicitement.

Inspecter l'état :

```bash
jq '.in_flight, .steps' .snap/progress.json
```

Repartir from scratch sur une feature :

```bash
jq 'del(.in_flight[] | select(.feature_id == "01-auth-email"))' \
   .snap/progress.json > .snap/progress.tmp && mv .snap/progress.tmp .snap/progress.json
```

### Partial-match feature_id donne plusieurs candidats

Depuis v1.0.0, partial-match n'est **plus** dans le helper (`progress.sh
resume` exige un id exact). C'est le `step-00-init.md` de chaque skill qui
fait le matching. Erreur typique :

```
Plusieurs features matchent 'auth' : 01-auth-email, 02-auth-sso. Précise.
```

→ utilise le `feature_id` complet.

## Sync plateforme

### `sync-push` échoue : `Platform error 429 / throttle`

Retry plus tard, ou côté plateforme augmente quota / API key scope.
`sync-push.sh` est idempotent (write-through outbox + ack), un retry ne
duplique pas la ressource.

### `manifest.refs.{X}.sync_status` reste `pending`

Inspecter :

```bash
jq '.refs' .snap/manifests/<feature_id>.manifest.json
```

`pending` = pas encore poussé (offline first run, ou échec silencieux).
Replay :

```text
/snap:fetch <feature_id>       # re-sync depuis remote (lecture)
```

Pour repush forcé : relance le skill qui a produit la ref
(`/snap:define --resume` repush PRD, etc.).

## Version mismatch & migration

### `MAJOR version mismatch detected`

Le plugin a été update (`git pull` sur `~/.claude/plugins/snap`) mais le
workspace local est à un schéma antérieur.

```text
/snap:upgrade --dry-run        # preview le plan
/snap:upgrade                  # applique (backup auto .snap.bak-v{x}-{ts}/)
```

### Workspace v0.6 (legacy `.claude/product/`)

```text
/snap:upgrade --from=0.6.0
```

Voir [migration-v1.md](migration-v1.md) pour les transformations détaillées.

## Tests & QA

### `/snap:qa` flaky verdicts à répétition

Cause typique : ordre de test non déterministe ou état partagé. `/snap:qa`
trace `qa_last_flaky_verdict` dans le ticket. Si `flaky` 2× consécutifs,
escalade : ouvre un ticket dédié `test-flakiness` plutôt que de réessayer.

### Playwright wireframe diff toujours en échec

- Vérifie que le ticket a `wireframe_url` (ou `design_url`) — sinon le diff
  n'a pas de référence.
- `qa.wireframe_check.tolerance` (config) : valeur trop stricte ? Default
  raisonnable autour de 0.05.
- MCP `playwright-mcp` actif ? `claude mcp list`.

## Où regarder ensuite

| Symptôme                               | Doc                                                |
| -------------------------------------- | -------------------------------------------------- |
| Comprendre la config                   | [configuration.md](configuration.md)               |
| Comprendre le flux global              | [workflow.md](workflow.md)                         |
| Comprendre la structure `.snap/`       | [structure.md](../contributing/structure.md)       |
| Comprendre un skill précis             | [skills/](skills/)                                 |
| MCP refs (Frame0, AFFiNE, Playwright…) | [mcp-refs.md](mcp-refs.md)                         |
