# Phase 7.5 — v0.5 `/design` skill + Figma platform + config nested (planifié, bloquant Phase 8)

**Objectif:** ajouter `/design` (skill optionnel parallèle à `/wireframe`, 3 modes : `ds-init`, `ds-update`, `mockup`), ouvrir `/wireframe` à Figma (via figma-mcp), introduire Bridge comme transport `/design` Figma, refactorer la config pour nester les blocs platform-specific (élimine pattern `{platform}_{key}` à plat). **Doit livrer avant Phase 8 — dogfooding consomme l'API v0.5.0.**

**Breaking** : bump 0.4 → 0.5.0. Pas de shim de compatibilité (plugin pilote, cohérent avec décision v0.2).

## 7.5.1 Décisions verrouillées

| #                 | Décision                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Scope `/design`   | 3 modes : bootstrap design system, mise à jour DS, génération maquettes hi-fi feature (avec ou sans wireframe en input) |
| Position pipeline | optionnel, parallèle ou séquentiel à `/wireframe`                                                                       |
| Liaison fichiers  | indépendant par défaut ; auto-suggestion lien si `wireframes.platform == design.platform` (AskUserQuestion preflight)   |
| Migration config  | breaking, pas de shim                                                                                                   |
| Figma split       | `/wireframe` → figma-mcp (raw `figma_execute`) ; `/design` → Bridge (CSpec compile → figma-console-mcp)                 |

## 7.5.2 Spike amont (0.5j — bloquant)

- [ ] Valider surface réelle `figma-mcp` (`figma_execute`, `exportAsync`, retour base64 vs filePath)
- [ ] Valider Bridge CLI runtime local : `setup`, `extract`, `compile`, `doctor`
- [ ] Confirmer license + maintenance Bridge + figma-console-mcp (MIT, activité)

## 7.5.3 Sub-phase 1 — Config schema refactor (breaking)

- [ ] **`wireframes` nested** : `frame0_api_port` → `wireframes.frame0.api_port` ; `penpot_export_dir` / `penpot_file_id` / `penpot_file_name` → `wireframes.penpot.{export_dir,file_id,file_name}` ; `export_source_dir` → `wireframes.frame0.export_source_dir`
- [ ] **`wireframes.figma`** ajouté : `{file_key, file_name, token_env}`
- [ ] **`wireframes.platform`** enum élargi : `frame0|penpot|figma`
- [ ] **Nouvelle section `design`** :

  ```jsonc
  "design": {
    "platform": "penpot|figma",
    "mode_defaults": {"mockup_canvas":"mobile-portrait|desktop|tablet", "design_system_source":"auto|file|none"},
    "export_format": "png|svg|pdf",
    "naming_pattern": "{feature_id}-{screen_name}-design",
    "penpot": {"file_id":null, "file_name":null, "export_dir":null, "design_system_page":"Components"},
    "figma":  {"file_key":null, "file_name":null, "token_env":"FIGMA_TOKEN", "bridge_kb_path":null, "bridge_transport":"console"}
  }
  ```

- [ ] **`tickets.schema.json`** : ajout champs optionnels `tickets[].{design_screen, design_url, design_mode}` (`mockup|reused`)
- [ ] **`load-config.sh`** : defaults nested + design ; suppression lecture clés plates
- [ ] **`setup-config.sh`** : wizard MAJ sections design opt-in
- [ ] Fixtures tests refresh complet

## 7.5.4 Sub-phase 2 — Helpers refactor + nouveaux

- [ ] **Decouple helpers config** : `frame0-helper.sh` + `penpot-helper.sh` ne lisent plus la config ; tous les params (`--api-port`, `--file-id`, `--export-dir`, `--format`) passés explicitement skill-side
- [ ] **`figma-helper.sh` (wireframe)** : mirror surface (`create-page`, `get-page`, `update-page`, `delete-page`, `list-pages`, `add-shapes`, `export-png`, `get-current-file`) ; backend descripteurs MCP `figma_execute` (raw Plugin API JS) + `exportAsync` ; params `--file-key`, `--page-id`, `--shapes-file`, `--output-path`, `--format`
- [ ] **`figma-bridge-helper.sh` (design)** : surface Bridge (`ds-init`, `ds-update`, `mockup-compile`, `extract-ds`, `export-shape`) ; params `--kb-path`, `--scene-graph-file`, `--transport=console|official`, `--token-env=FIGMA_TOKEN`
- [ ] **Tests** : `test-figma-helper.sh` (~60 tests, mirror penpot), `test-figma-bridge-helper.sh` (~40 tests axés compile descriptors + KB validation), refresh `test-frame0-helper.sh` / `test-penpot-helper.sh` post-decoupling

## 7.5.5 Sub-phase 3 — `/wireframe` skill — Figma + nested config + decouple

- [ ] **step-00** : §5.c préflight figma (figma-mcp reachable + Figma Desktop running + `get-current-file` match `wireframes.figma.file_key`) ; résolution config nested propagée en variables shell
- [ ] **step-02** : §3.c export figma (`figma-helper.sh export-png` avec params explicites) ; tableau platform → helper → backend MAJ
- [ ] **SKILL.md + docs/skills/wireframe.md** : 3 platforms

## 7.5.6 Sub-phase 4 — `/design` skill (nouveau)

- [ ] **Args** : `/design [--resume|-r] [--feature=ID] [--mode=ds-init|ds-update|mockup] [--dry-run]`
- [ ] **Mode resolver step-00** : auto-detect (`ds-init` si DS absent, `ds-update` si diff specs/file, `mockup` si feature_id + tickets UI, AskUserQuestion sinon)
- [ ] **Pipeline 6 steps** :
  - step-00 init (parse args, resolve feature+mode, load config.design, préflight platform-specific, liaison auto si platform match)
  - step-01 ds-bootstrap (modes ds-init / ds-update)
  - step-02 source-resolve (mode mockup — détecte wireframes existants, sinon part des tickets)
  - step-03 mockup (per screen×state : frame hi-fi, applique composants DS, export asset)
  - step-04 gallery (page Docs `design-gallery` séparée wireframes-gallery)
  - step-05 link (tickets `design_url` + `design_screen` + `design_mode`)
- [ ] **Préflight `design`** : platform enum `penpot|figma` (frame0 exclu — low-fi only)
- [ ] **Liaison auto** : si `wireframes.platform == design.platform` ET binding wireframes défini ET `design.{plat}.file_id` null → AskUserQuestion (Yes / No, fichier séparé / Save link in config)
- [ ] **Helpers usage** : Penpot → `penpot-helper.sh` (réutilisé, fidélité contrôlée skill-side) ; Figma → `figma-bridge-helper.sh`
- [ ] **Templates créés** : `_shared/templates/docs-defaults/design-gallery.md`, `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml`
- [ ] **Tests** : `test-design-e2e.sh` (3 sub-suites : ds-init, ds-update, mockup) ; `test-design-mode-resolver.sh` (heuristique mode auto)

## 7.5.7 Sub-phase 5 — Wiring workflow

- [ ] **`resume-state.sh`** : dispatch `--skill=design` (état per-mode)
- [ ] **Lifecycle scripts** : `pre_design` / `post_design` enum + doc
- [ ] **`/develop` step-00** : check `tickets[].design_url` présent → mention designer-handoff dans review thread (non bloquant si absent)
- [ ] **`/qa` step-04** : option `design_check` (compare implem vs design asset si présent, opt-in `qa.design_check.enabled`)
- [ ] **`/snap:doc-update`** : ingère assets design en plus des wireframes pour update doc fonctionnelle

## 7.5.8 Sub-phase 6 — Docs, migration, CI

- [ ] **`docs/config.md`** : schema nested + section design + exemples (Penpot, Figma, mixed)
- [ ] **`docs/skills/design.md`** : nouveau (mirror `docs/skills/wireframe.md`)
- [ ] **`docs/skills/wireframe.md`** : figma platform ajouté
- [ ] **`docs/decisions.md`** : "config nested per platform", "Bridge réservé `/design` Figma"
- [ ] **`CHANGELOG.md`** : entry BREAKING v0.5.0 avec mapping migration explicite (tableau ancien → nouveau)
- [ ] **Migration utilisateur** : breaking, doc mapping CHANGELOG ; optionnel `scripts/migrate-config-v04-to-v05.sh` (jq-based one-shot, non-bundlé)
- [ ] **CI** : shellcheck nouveaux helpers ; JSON schema validation fixtures nested ; tests E2E matrice wireframe (3 platforms × dry-run + mock MCP) + design (3 modes × 2 platforms = 6 paths)

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
