# Phase 11.6 — v0.3+ Penpot wireframe platform (livré)

**Objectif:** ouvrir `/wireframe` à un second moteur (Penpot web app) en plus de Frame0, sans dupliquer la logique d'orchestration.

- [x] **Config schema** — `wireframes.platform` enum élargie à `"penpot"`, ajout des champs `penpot_export_dir` (path absolu), `penpot_file_id` (UUID préflight binding), `penpot_file_name` (informationnel)
- [x] **`penpot-helper.sh`** — mirror complet de l'API `frame0-helper.sh` : `create-page`, `get-page`, `update-page`, `delete-page`, `list-pages`, `add-shapes`, `export-png`, plus `get-current-file` (préflight). CRUD via descripteur MCP `execute_code` (JS construit côté helper avec `penpot.createPage()`, `createRectangle()`, `createText()`, `createEllipse()`, `penpotUtils.getPageById()` …), export via `export_shape` (filePath absolu obligatoire)
- [x] **Préflight Penpot** (`step-00-init.md` §5.b) — vérifie qu'un fichier est ouvert dans l'onglet browser où le plugin MCP est connecté ; mismatch `penpot_file_id` → halt avec message clair ; binding absent → `AskUserQuestion` avec option "Save to config"
- [x] **Skill refactor platform-neutral** — `step-00` / `step-02` / `SKILL.md` séparent prose générique des blocs `frame0` / `penpot` clairement étiquetés (§5.a / §5.b, §3.a / §3.b)
- [x] **Single-format guard** — `step-02` résout `$fmt` une seule fois depuis `wireframes.export_format`, extension de fichier dérivée (`${page_title}.${fmt}`), `--format` retiré des invocations doc, règle explicite "exactly one export per page" (corrige run récent qui exportait PNG + SVG simultanément)
- [x] **Tests** — `tests/test-penpot-helper.sh` (66 tests : action enum, validation args, descripteur MCP shape, JS code, dry-run, export-png filePath absolu, `get-current-file`) ; tests frame0 + e2e wireframe préservés (97 + 22)
- [x] **Docs** — `docs/config.md` (champs penpot ajoutés), `docs/skills/wireframe.md` (table "Plateformes supportées", section "Penpot MCP tools utilisés"), CHANGELOG entries
- [x] **CI** — shellcheck SC2034 résolu (`PARENT_ID` inutilisé droppé, Penpot pages = file-scoped)

**Sortie:** `/wireframe` opère identiquement sur Frame0 (desktop + HTTP API) et Penpot (web + plugin MCP) ; bascule = un seul champ config.
