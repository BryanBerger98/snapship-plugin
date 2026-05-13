# Phase 7.5 — v0.5 `/design` skill + Figma platform + config nested (livrée — 2026-05-13, gate Phase 8 ouvert)

**Objectif:** ajouter `/design` (skill optionnel parallèle à `/wireframe`, 3 modes : `ds-init`, `ds-update`, `mockup`), ouvrir `/wireframe` à Figma (via figma-mcp), introduire Bridge comme transport `/design` Figma, refactorer la config pour nester les blocs platform-specific (élimine pattern `{platform}_{key}` à plat). **Doit livrer avant Phase 8 — dogfooding consomme l'API v0.5.0.**

**Breaking** : bump 0.4 → 0.5.0. Pas de shim de compatibilité (plugin pilote, cohérent avec décision v0.2).

## 7.5.1 Décisions verrouillées

| #                 | Décision                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Scope `/design`   | 3 modes : bootstrap design system, mise à jour DS, génération maquettes hi-fi feature (avec ou sans wireframe en input) |
| Position pipeline | optionnel, parallèle ou séquentiel à `/wireframe`                                                                       |
| Liaison fichiers  | indépendant par défaut ; auto-suggestion lien si `wireframes.platform == design.platform` (AskUserQuestion preflight)   |
| Migration config  | breaking, pas de shim                                                                                                   |
| Serveur MCP Figma | **Unique** : `southleft/figma-console-mcp` (~100 outils, MIT, actif) pour `/wireframe` ET `/design`                       |
| Couches Figma     | `/wireframe` → `figma-console-mcp` direct (outil `figma_execute`, JS Plugin API brut) ; `/design` → CLI `bridge-ds compile` (YAML CSpec → JS conforme système design) puis transport `official` = injection via `figma_execute` du même MCP, ou `console` = collage manuel DevTools |
| Bridge            | **CLI séparé** (`noemuch/bridge`, MIT, v3.0.0), pas serveur MCP. Installé en dépendance Node.js. Plugin Claude Code parallèle.            |

## 7.5.2 Validation préalable (0.5j — bloquant, livrée)

- [x] **Serveur MCP Figma identifié** : `southleft/figma-console-mcp` (~100 outils, MIT, v1.23.0 mai 2026, 1.7k★). Outil principal `figma_execute` (JS Plugin API brut, retour JSON nœuds créés). Pas d'`exportAsync` natif côté MCP — exports via `figma_execute` injectant `node.exportAsync()` (retour base64 inline). Couleurs format `{r,g,b,a}` plages 0-1 (pas 0-255). Batch max 100 items/appel.
- [x] **Bridge CLI confirmé** : `noemuch/bridge` (MIT, v3.0.0 mars 2026, 145★, TypeScript). Commandes `bridge-ds setup` / `compile` / `doctor` / `extract` / `cron`. Compile YAML CSpec → JSON scene graph + code JS Plugin API conforme système design (26 règles Figma appliquées). Distribution npm.
- [x] **Prérequis utilisateur** : Figma Desktop lancé, plugin "Desktop Bridge" installé dans Figma (canal WebSocket ports 9223–9232), variable env `FIGMA_ACCESS_TOKEN` (token API personnel), Node.js 18+.
- [x] **Décision verrouillée** : un seul serveur MCP Figma pour les deux skills ; Bridge = CLI compilateur séparé, sortie injectée via `figma_execute` du même MCP (transport `official`) ou collage manuel DevTools (transport `console`).

## 7.5.3 Sub-phase 1 — Config schema refactor (breaking)

- [x] **`wireframes` nested** : `frame0_api_port` → `wireframes.frame0.api_port` ; `penpot_export_dir` / `penpot_file_id` / `penpot_file_name` → `wireframes.penpot.{export_dir,file_id,file_name}` ; `export_source_dir` → `wireframes.frame0.export_source_dir`
- [x] **`wireframes.figma`** ajouté : `{file_key, file_name, token_env}`
- [x] **`wireframes.platform`** enum élargi : `frame0|penpot|figma`
- [x] **Nouvelle section `design`** :

  ```jsonc
  "design": {
    "platform": "penpot|figma",
    "mode_defaults": {"mockup_canvas":"mobile-portrait|desktop|tablet", "design_system_source":"auto|file|none"},
    "export_format": "png|svg|pdf",
    "naming_pattern": "{feature_id}-{screen_name}-design",
    "penpot": {"file_id":null, "file_name":null, "export_dir":null, "design_system_page":"Components"},
    "figma":  {"file_key":null, "file_name":null, "token_env":"FIGMA_TOKEN", "bridge_kb_path":null, "bridge_transport":"official"}
  }
  ```

- [x] **`tickets.schema.json`** : ajout champs optionnels `tickets[].{design_screen, design_url, design_mode}` (`mockup|reused`)
- [x] **`load-config.sh`** : defaults nested + design ; suppression lecture clés plates
- [x] **`setup-config.sh`** : wizard MAJ sections design opt-in
- [x] Fixtures tests refresh complet

## 7.5.4 Sub-phase 2 — Helpers refactor + nouveaux

- [x] **Decouple helpers config** : `frame0-helper.sh` + `penpot-helper.sh` ne lisent plus la config ; tous les params (`--api-port`, `--file-id`, `--export-dir`, `--format`) passés explicitement skill-side
- [x] **`figma-helper.sh` (wireframe)** : miroir surface penpot (`create-page`, `get-page`, `update-page`, `delete-page`, `list-pages`, `add-shapes`, `export-png`, `get-current-file`) ; backend = descripteurs MCP `figma_execute` du serveur `figma-console-mcp` (Plugin API JS construit côté helper, exports via `node.exportAsync()` injecté retour base64 inline → décodage et écriture disque côté helper) ; params `--file-key`, `--page-id`, `--shapes-file`, `--output-path`, `--format`
- [x] **`figma-bridge-helper.sh` (design)** : surface Bridge (`ds-init`, `ds-update`, `mockup-compile`, `extract-ds`, `export-shape`) ; backend = invocation CLI `bridge-ds compile` (YAML CSpec → JS Plugin API conforme système design) puis injection sortie selon transport : `official` = `figma_execute` du même `figma-console-mcp` (défaut), `console` = écriture fichier `.js` + instruction utilisateur collage DevTools Figma ; params `--kb-path`, `--scene-graph-file`, `--transport=official|console`, `--token-env=FIGMA_TOKEN`
- [x] **Tests** : `test-figma-helper.sh` (~60 tests, mirror penpot), `test-figma-bridge-helper.sh` (~40 tests axés compile descriptors + KB validation), refresh `test-frame0-helper.sh` / `test-penpot-helper.sh` post-decoupling

## 7.5.5 Sub-phase 3 — `/wireframe` skill — Figma + nested config + decouple

- [x] **step-00** : §5.c vérification préalable figma (`figma-console-mcp` joignable + Figma Desktop lancé + plugin "Desktop Bridge" connecté WebSocket + `get-current-file` correspond à `wireframes.figma.file_key`) ; résolution config nesté propagée en variables shell
- [x] **step-02** : §3.c export figma (`figma-helper.sh export-png` avec params explicites) ; tableau platform → helper → backend MAJ
- [x] **SKILL.md + docs/skills/wireframe.md** : 3 platforms

## 7.5.6 Sub-phase 4 — `/design` skill (nouveau)

- [x] **Args** : `/design [--resume|-r] [--feature=ID] [--mode=ds-init|ds-update|mockup] [--dry-run]`
- [x] **Mode resolver step-00** : auto-detect (`ds-init` si DS absent, `ds-update` si diff specs/file, `mockup` si feature_id + tickets UI, AskUserQuestion sinon)
- [x] **Pipeline 6 steps** :
  - step-00 init (parse args, resolve feature+mode, load config.design, préflight platform-specific, liaison auto si platform match)
  - step-01 ds-bootstrap (modes ds-init / ds-update)
  - step-02 source-resolve (mode mockup — détecte wireframes existants, sinon part des tickets)
  - step-03 mockup (per screen×state : frame hi-fi, applique composants DS, export asset)
  - step-04 gallery (page Docs `design-gallery` séparée wireframes-gallery)
  - step-05 link (tickets `design_url` + `design_screen` + `design_mode`)
- [x] **Préflight `design`** : platform enum `penpot|figma` (frame0 exclu — low-fi only)
- [x] **Liaison auto** : si `wireframes.platform == design.platform` ET binding wireframes défini ET `design.{plat}.file_id` null → AskUserQuestion (Yes / No, fichier séparé / Save link in config)
- [x] **Helpers usage** : Penpot → `penpot-helper.sh` (réutilisé, fidélité contrôlée skill-side) ; Figma → `figma-bridge-helper.sh`
- [x] **Templates créés** : `_shared/templates/docs-defaults/design-gallery.md`, `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml`
- [x] **Tests** : `test-design-e2e.sh` (3 sub-suites : ds-init, ds-update, mockup) ; `test-design-mode-resolver.sh` (heuristique mode auto)

## 7.5.7 Sub-phase 5 — Wiring workflow

- [x] **`resume-state.sh`** : dispatch `--skill=design` (état per-mode)
- [x] **Lifecycle scripts** : `pre_design` / `post_design` enum + doc
- [x] **`/develop` step-00** : check `tickets[].design_url` présent → mention designer-handoff dans review thread (non bloquant si absent)
- [x] **`/qa` step-04** : option `design_check` (compare implem vs design asset si présent, opt-in `qa.design_check.enabled`)
- [x] **`/snap:doc-update`** : ingère assets design en plus des wireframes pour update doc fonctionnelle

## 7.5.8 Sub-phase 6 — Docs, migration, CI

- [x] **`docs/config.md`** : schema nested + section design + exemples (Penpot, Figma, mixed)
- [x] **`docs/skills/design.md`** : nouveau (mirror `docs/skills/wireframe.md`)
- [x] **`docs/skills/wireframe.md`** : figma platform ajouté
- [x] **`docs/decisions.md`** : "config nested per platform", "Bridge réservé `/design` Figma"
- [x] **`CHANGELOG.md`** : entry BREAKING v0.5.0 avec mapping migration explicite (tableau ancien → nouveau)
- [x] **Migration utilisateur** : breaking, doc mapping CHANGELOG ; optionnel `scripts/migrate-config-v04-to-v05.sh` (jq-based one-shot, non-bundlé)
- [x] **CI** : shellcheck nouveaux helpers ; JSON schema validation fixtures nested ; tests E2E matrice wireframe (3 platforms × dry-run + mock MCP) + design (3 modes × 2 platforms = 6 paths)

## 7.5.9 Estimation effort

| Sub-phase                                   | Effort     | Risques                                 |
| ------------------------------------------- | ---------- | --------------------------------------- |
| Spike Bridge + figma-mcp                    | 0.5j       | API runtime à valider                   |
| 1 — Config nested + design + tickets schema | 0.5j       | impact fixtures large                   |
| 2 — Helpers refactor + figma + figma-bridge | 3j         | Bridge CLI + figma_execute runtime      |
| 3 — /wireframe figma + decouple             | 1j         | préflight Figma Desktop                 |
| 4 — /design skill (3 modes)                 | 4j         | scope DS bootstrap, mockup-from-tickets |
| 5 — Wiring develop/qa/doc-update            | 1j         | retests existants                       |
| 6 — Docs + CI + migration                   | 1.5j       | doc churn massif                        |
| **Total v0.5.0**                            | **~11.5j** | scope ambitieux                         |

## 7.5.10 Ordre d'exécution

1. Spike (0.5j) → décision continue/abort
2. Sub-phase 1 (config) → tests verts avant toute autre tâche
3. Sub-phase 2.1 (decouple helpers existants) → tests verts
4. Sub-phase 2.2 + 2.3 (figma-helper + figma-bridge-helper) — parallélisables
5. Sub-phase 3 (/wireframe figma)
6. Sub-phase 4 mode `mockup` d'abord, puis modes `ds-*` (itératif)
7. Sub-phase 5 + 6 (wiring + docs)

**Sortie:** v0.5.0 — config nested, 3 platforms wireframe (frame0 + penpot + figma), skill `/design` opérationnel sur Penpot + Figma (via Bridge) avec 3 modes (ds-init, ds-update, mockup), liaison auto fichiers si platforms identiques. **Gate Phase 8 ouvert.**
