# Changelog

All notable changes to snapship-plugin documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed — `/design` réduit aux maquettes, retrait du tooling Bridge CLI (breaking)

- **`/design` ne fait plus qu'une seule chose : des maquettes hi-fi.**
  Suppression des modes `ds-extract` / `ds-init` / `ds-update`. Le design
  system est désormais géré hors plugin.
- **Input `/design`** — prend un `<ticket-id|feature-id>` (comme `/develop`
  et `/qa`) et construit les maquettes d'après ce que le ticket demande. Un
  ticket id cible un ticket ; un feature id batch tous les tickets UI.
- **Retrait du CLI `bridge-ds`** (repo `noemuch/bridge`) et de tout son
  tooling : helpers `figma-bridge-helper.sh` + `design-mode-resolver.sh`,
  templates `design-system-defaults/`, tests `test-figma-bridge-helper.sh` +
  `test-design-mode-resolver.sh`, steps `step-01-ds-bootstrap.md` +
  `step-01b-ds-extract.md`.
- **`/design figma` utilise le même `figma-helper.sh`** et le même plugin
  Desktop Bridge que `/wireframe figma` — surface Figma unifiée, un seul
  helper à maintenir.
- **Config** — clés retirées : `design.extract` (bloc entier),
  `design.figma.bridge_kb_path`, `design.figma.bridge_transport`. Schema
  `additionalProperties:false` rejette les anciennes clés.
- **Pipeline `/design` renuméroté** — `step-00-init` → `step-01-source-resolve`
  → `step-02-mockup` → `step-03-gallery` → `step-04-link`.
- **Lecture DS optionnelle** — `design.mode_defaults.design_system_source`
  (`none|file|auto`) : le fichier DS configuré peut être **lu** en référence
  de composants, jamais écrit.
- **Note** — le **plugin Desktop Bridge** (plugin Figma, canal WebSocket de
  `figma-console-mcp`) reste requis ; il n'a aucun lien avec le CLI
  `bridge-ds` retiré (deux entités distinctes qui partageaient le nom).
- **Docs** — `docs/skills/design.md`, `docs/config.md`, `docs/mcp-refs.md`,
  `docs/decisions.md`, `docs/README.md`, `README.md`, `plugin.json` mis à jour.

### Changed — secrets isolés via `.env.snapship`

- **Token Figma chargé depuis `.env.snapship`** (racine projet, gitignored)
  au lieu de la shell env directement. Skills `/design` figma + `/wireframe`
  figma appellent `skills/_shared/load-env.sh --project-root="$PWD"
  --key=<NAME>` puis exportent la valeur pour `figma-console-mcp`. Clé par
  défaut `FIGMA_ACCESS_TOKEN` (override toujours via
  `design.figma.token_env` / `wireframes.figma.token_env`).
- **Nouveau helper `skills/_shared/load-env.sh`** — parser KEY=VALUE simple
  (commentaires `#`, quotes strippées, pas de substitution shell).
  Mode `--key=NAME` retourne valeur ou exit 1. Mode sans `--key` dump tout
  (utilisable avec `eval`). Tests : 12/12 pass.
- **`.gitignore`** — ajoute `.env.snapship` + `.env.snapship.*` (secrets
  per-projet ne doivent jamais être commit).
- **Docs** — `docs/config.md` nouvelle section "Secrets : `.env.snapship`"
  (format + résolution + erreurs courantes). `docs/skills/design.md` +
  `docs/skills/wireframe.md` mis à jour pour pointer sur le nouveau flux.
- **Raison** : config commit-friendly (`snapship.config.json`) ne doit pas
  contenir de secrets. Pattern habituel `.env.<nom>` pour secrets per-projet
  isolés (Vercel, Next.js, etc.).

## [0.6.0] — 2026-05-13

### Added — `/design --mode=ds-extract` (LLM-driven React → YAML CSpec one-shot)

- **Nouveau mode `ds-extract`** sur le skill `/design` — Claude lit les
  composants React existants sous `design.extract.source` et émet
  directement les YAML CSpec sous `design-system/specs/`. Bootstrap
  one-shot code → YAML → Figma. Après init, **Figma = source de vérité**
  (pas de reverse sync). Pour propager Figma → code, utiliser Figma Dev
  Mode + Code Connect (hors scope).
- **LLM-driven, stack-agnostic.** Pas de parser dédié, pas de Node CLI,
  pas de build. Marche sur Tailwind+cva, styled-components, CSS Modules,
  MUI, vanilla CSS, et patterns custom (HOC, render props). Trade-off
  assumé : non-déterministe, mais relu par user avant push Figma.
- **Mode explicit-only** — `ds-extract` n'est jamais auto-résolu par
  `step-00`. Doit être passé via `--mode=ds-extract` explicitement, pour
  éviter de re-générer le YAML après que Figma soit devenu source de
  vérité (sinon `ds-update` clobber les édits design).
- **Flag `--chain-init`** — enchaîne automatiquement dans `ds-init` après
  extract (pipeline complet code → YAML → Figma en une commande).
- **Classification atomic/molecular/organism** par analyse graphe
  d'imports (fixed-point) avec override commentaire
  `// @ds-category: organism`.
- **Si Tailwind détecté** — Claude lit `tailwind.config.{ts,mjs,cjs,js}`
  pour mapper classes → tokens (`bg-brand-500` → `{colors.brand.500}`).
- **`skills/design/step-01b-ds-extract.md`** (nouveau step) — instructions
  LLM-driven : validation source, pre-flight Figma confirmation, lecture
  composants, classification, émission YAML, persiste
  `.design-cache.json` flag `extract.ran_at`, chaîne dans step-01 si
  `--chain-init`.
- **Config `design.extract`** (opt-in) — trois clés seulement :
  `source` (`src/components`), `out` (`design-system/specs`),
  `category_override_marker` (`@ds-category`). Défauts résolus par
  `load-config.sh` uniquement si bloc présent (skill désactivé sinon).
- **`setup-config.sh`** — nouveaux flags wizard
  `--design-extract-opt-in=true|false` + flags granulaires
  `--design-extract-source`, `--design-extract-out`. Tests : 35/35 pass.
- **`skills/design/SKILL.md`** + `step-00-init.md` mis à jour — `ds-extract`
  ajouté à la table des modes, parse args supporte `--mode=ds-extract` +
  `--chain-init`, mode resolver short-circuit (skip auto-detect pour
  `ds-extract`), routing `step-00` → `step-01b` → optionnellement `step-01`.

### Added — Schema config v0.6

- **`design.extract`** ajouté au JSON Schema (`config.schema.json`) avec
  `additionalProperties: false`, défauts inline. 30/30 schema tests pass.
- **`load-config.sh`** — bloc `design.extract` résolu uniquement si présent
  dans la config (skill désactivé par défaut). 47/47 tests pass.

### Docs

- **`docs/skills/design.md`** — section `ds-extract` ajoutée avec flow
  LLM-driven, config opt-in, contrainte Figma-source-of-truth post-init.
- **`docs/config.md`** — bloc `design.extract` documenté.
- **`docs/decisions.md`** — décision "v0.6 — ds-extract one-shot React → YAML"
  ajoutée (rationale LLM-driven vs parser AST, explicit-only, no reverse sync).
- **`docs/roadmap/phase-07.6-ds-extract.md`** — spec Phase 7.6.

## [0.5.0] — 2026-05-13

### Added — `/design` skill (3 modes : ds-init, ds-update, mockup)

- **Nouveau skill `/design`** — optionnel, parallèle ou séquentiel à
  `/wireframe`. 6 steps end-to-end (init → ds-bootstrap → source-resolve →
  mockup → gallery → link). Mode auto-résolu en step-00 :
  - `ds-init` — bootstrap design system depuis
    `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml`.
  - `ds-update` — diff specs vs file → patch in place (upsert composants
    par nom, cache `.design-cache.json` avec `specs_hash`).
  - `mockup` — par `(screen_id, state)`, frame hi-fi appliquant composants
    DS, export asset, lien tickets UI.
- **Plateformes supportées** : `penpot` (helper `penpot-helper.sh` réutilisé,
  fidélité contrôlée skill) ou `figma` (helper `figma-bridge-helper.sh` via
  CLI `bridge-ds`). `frame0` exclu (low-fi only).
- **Auto-link wireframes ↔ design** — si `wireframes.platform == design.platform`
  ET binding wireframes défini ET `design.{plat}.{file_id|file_key}` null →
  `AskUserQuestion` step-00 propose de réutiliser le même fichier.
- **Mode resolver** (`_shared/design-mode-resolver.sh`) — heuristique par
  signal (DS file binding vide + YAML defaults → `ds-init` ; binding set +
  diff specs → `ds-update` ; `--feature` ou tickets UI unflagged → `mockup`).
  Ambiguïté → `AskUserQuestion`.
- **Préflight** : MCP (`check-mcp-required.sh --skill=design`),
  Penpot (`get-current-file` vs `design.penpot.file_id`),
  Figma (token env + `figma.fileKey` vs `design.figma.file_key` +
  `bridge-ds` joignable).
- **Templates bundlés** : `_shared/templates/docs-defaults/design-gallery.md`,
  `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml`.
- **`figma-bridge-helper.sh`** (nouveau) — surface : `ds-init`, `ds-update`,
  `mockup-compile`, `extract-ds`, `export-shape`. Backend : invocation CLI
  `bridge-ds compile` (YAML CSpec → JS Plugin API conforme système design) +
  injection selon transport (`official` = `figma_execute` du
  `figma-console-mcp` ; `console` = écriture `.js` + collage manuel
  DevTools). Tests : `tests/test-figma-bridge-helper.sh` (76/76 pass).
- **Tickets schema** — ajout champs optionnels `design_screen`, `design_url`,
  `design_mode` (`mockup|reused`) sur `tickets[]`.
- **Lifecycle hooks** `pre_design` / `post_design` ajoutés à
  `lifecycle_scripts` enum.
- **`/develop` step-00** — banner designer-handoff si `tickets[].design_url`
  présent (non bloquant si absent).
- **`/qa` step-04** — option `design_check` (opt-in
  `qa.design_check.enabled`). Mode `asset-presence` (défaut) ou `playwright`
  (futur).
- **`/snap:doc-update`** — ingère assets design en plus des wireframes dans
  bundles journey.
- **`resume-state.sh --skill=design`** — state per-mode (`ds-init`,
  `ds-update`, `mockup` resument indépendamment).
- Tests : nouvelles suites `test-design-e2e.sh` (19/19), 
  `test-design-mode-resolver.sh` (15/15).

### Added — Figma platform pour `/wireframe`

- **`wireframes.platform`** accepte `"figma"` (en plus de `"frame0"` /
  `"penpot"`). Helper `figma-helper.sh` expose la même surface que les
  autres helpers (`create-page`, `get-page`, `update-page`, `delete-page`,
  `list-pages`, `add-shapes`, `export-png`, `get-current-file`, plus
  `save-export` pour décoder le base64 inline retourné par
  `figma_execute`).
- **Backend** — MCP unique `figma-console-mcp` (southleft, MIT, ~100 tools)
  via outil `figma_execute` (JS Plugin API brut, retour JSON nœuds créés).
  Couleurs converties `#hex` → `{r,g,b}` 0–1 côté helper (convention
  Figma). Exports via `node.exportAsync()` retour base64 inline →
  `save-export` décode et écrit disque.
- **Prérequis utilisateur** — Figma Desktop lancé, plugin "Desktop Bridge"
  installé (canal WebSocket ports 9223–9232), `$FIGMA_ACCESS_TOKEN` (ou
  variable nommée `wireframes.figma.token_env`), Node.js 18+.
- **Préflight step-00** — `get-current-file` compare `figma.fileKey` à
  `wireframes.figma.file_key`. Mismatch → halt clair. Vide → flow
  AskUserQuestion (Save to config).
- Tests : `tests/test-figma-helper.sh` (116/116 pass).

### Changed — Config schema nested per-platform (breaking)

- **`wireframes`** : les clés platform-specific deviennent des blocs nested
  (`wireframes.{frame0,penpot,figma}`). `additionalProperties: false`
  rejette les anciennes clés plates.
- **`design`** : nouvelle section parallèle à `wireframes`. Optionnelle,
  absente = skill `/design` désactivé.
- **Helpers context-agnostic** — `frame0-helper.sh`, `penpot-helper.sh`,
  `figma-helper.sh`, `figma-bridge-helper.sh` ne lisent plus la config.
  Tous les params (`--api-port`, `--file-id`, `--file-key`, `--export-dir`,
  `--format`, `--kb-path`, `--transport`, `--token-env`) sont passés
  explicitement skill-side. `step-00` résout les valeurs nested et persiste
  dans l'état du skill.
- **`setup-config.sh` wizard** — sections design opt-in.
- **`load-config.sh`** — defaults injectés sur les blocs nested
  (`wireframes.figma.token_env`, `design.export_format`,
  `design.naming_pattern`, `design.mode_defaults.*`, `design.figma.*`,
  `design.penpot.design_system_page`). Lecture des clés plates v0.4
  supprimée.

#### Mapping migration v0.4 → v0.5

| v0.4 (plat)                       | v0.5 (nested)                        |
| --------------------------------- | ------------------------------------ |
| `wireframes.frame0_api_port`      | `wireframes.frame0.api_port`         |
| `wireframes.export_source_dir`    | `wireframes.frame0.export_source_dir`|
| `wireframes.penpot_export_dir`    | `wireframes.penpot.export_dir`       |
| `wireframes.penpot_file_id`       | `wireframes.penpot.file_id`          |
| `wireframes.penpot_file_name`     | `wireframes.penpot.file_name`        |
| —                                 | `wireframes.figma.{file_key,file_name,token_env}` (nouveau) |
| —                                 | `design.*` (nouvelle section)        |
| —                                 | `tickets[].design_screen / design_url / design_mode` (nouveau) |

### Added — Migration script v0.4 → v0.5

- **`scripts/migrate-config-v04-to-v05.sh`** (jq one-shot, non-bundlé
  runtime). Lit `snapship.config.json` v0.4, écrit v0.5 nested. Idempotent
  (no-op si déjà v0.5). Backup `.bak` créé.
- Tests : `tests/test-migrate-config-v04-to-v05.sh` (17/17 pass), couvre
  no-op idempotent, mapping complet, validation post-migration contre
  schema v0.5.

### Changed — Helpers shared structured metadata

- **`telemetry.sh`** et **`update-progress.sh`** acceptent désormais
  `--extra=JSON` (objet JSON merge dans l'event/log NDJSON). Permet aux
  steps de logguer du contexte structuré (mode design, specs_count,
  linked_tickets, …) sans inflater l'API en arguments.

### Fixed — `/wireframe` exports a single asset per page (config-driven format)

- **step-02-design.md** : ajout explicite "Exactly one export per page"
  + bloc dédié "Resolve export format (once, at start of step)" qui lit
  `config.wireframes.export_format` une seule fois et stocke dans `$fmt`.
- Exemples d'invocation `export-png` débarrassés du `--format=png` codé en
  dur ; le helper retombe automatiquement sur la config. Note "DO NOT
  pass --format here" pour bloquer toute dérive.
- Extension de fichier dérivée de `$fmt` (`${page_title}.${fmt}`) au lieu
  de `.png` codé en dur — l'agent ne peut plus deviner qu'il faudrait
  produire `.svg` en plus pour faire correspondre la config.
- **Pourquoi** : un run récent avait produit simultanément des PNG et des
  SVG car la doc hardcodait `--format=png` alors que la config disait
  `svg`. Le modèle a interprété la divergence en exportant les deux.
  La résolution unique côté config rend le format mono-source.

### Changed — Skill `/wireframe` platform-neutral wording

- **SKILL.md** : description et pipeline reformulés sans mention exclusive
  de Frame0. Nouvelle table "Supported platforms" explicite le mapping
  `wireframes.platform` → helper. Outputs/args neutralisés.
- **step-00-init.md** : préflight Frame0 (§5.a) et Penpot (§5.b) clairement
  séparés sous des en-têtes dédiés au lieu de prose mixte.
- **step-02-design.md** : export PNG scindé en blocs §3.a (frame0, HTTP
  bypass + format enum complet) et §3.b (penpot, `export_shape` filePath
  absolu + format enum restreint). Failure handling éclaté générique vs
  platform-specific.
- **Pourquoi** : éviter les ambiguïtés quand l'utilisateur passe d'une
  plateforme à l'autre — chaque section nommée renvoie sans équivoque
  au comportement attendu pour son moteur.

### Added — Penpot file binding preflight

- **`wireframes.penpot_file_id` + `penpot_file_name`** (schema config) —
  UUID + nom human-readable du fichier Penpot ciblé. Penpot MCP **ne peut
  pas ouvrir un fichier par programme** : le fichier ciblé = celui ouvert
  dans l'onglet browser où le plugin Penpot MCP est chargé et connecté.
- **`penpot-helper.sh get-current-file`** (nouveau) — action sans arg,
  émet descripteur `execute_code` retournant `{id, name}` de
  `penpot.currentFile`. Skill step-00 l'appelle au préflight.
- **`step-00-init.md` 5b** — préflight binding fichier Penpot :
  - Appelle `get-current-file`. Si "no plugin connected" → halt avec
    instruction (ouvrir fichier + charger plugin + connect).
  - Si `penpot_file_id` set en config → compare. Mismatch = halt avec
    message clair (expected vs got).
  - Pas de `penpot_file_id` → `AskUserQuestion` confirme + propose
    "Save to config" pour persister le binding.
- **Tests** : +6 (action `get-current-file` JS shape, exit code, descriptor
  shape, comportement read-action sous dry-run). 66/66 pass.

### Added — Penpot wireframe platform support

- **`wireframes.platform`** accepte désormais `"penpot"` en plus de `"frame0"`
  (schema config). Le skill `/wireframe` dispatche sur le helper correspondant
  selon la config résolue à step-00.
- **`skills/_shared/penpot-helper.sh`** (nouveau) — mirror de l'API de
  `frame0-helper.sh` (actions `create-page`, `get-page`, `update-page`,
  `delete-page`, `list-pages`, `add-shapes`, `export-png`). Chaque action
  émet un descripteur MCP (exit 10) ciblant l'outil Penpot adéquat :
  - Tous les CRUD passent par l'outil MCP `execute_code` avec un blob JS
    construit côté helper (utilise `penpot.createPage()`, `createRectangle()`,
    `createText()`, `createEllipse()`, `penpotUtils.getPageById()`, etc.).
    Globals disponibles : `penpot`, `penpotUtils`, `storage`, `console`.
  - `export-png` route vers l'outil MCP `export_shape` (params `shapeId`,
    `format=png|svg`, `filePath` **absolu**). Penpot écrit le fichier
    directement sur disque — pas de décode base64 local, pas de bypass
    HTTP (contrairement à Frame0).
- **`wireframes.penpot_export_dir`** (nouveau, schema config) — répertoire
  par défaut pour les exports Penpot. Doit être absolu (contrainte Penpot
  MCP). Défaut runtime : `{project_root}/.claude/product/features/{feature_id}/wireframes/`.
- **Schéma shape unifié** entre frame0 et penpot pour `add-shapes` :
  `{type:"text|rect|ellipse", name, x, y, width, height, text, fill}`. Les
  helpers normalisent chacun vers leur SDK natif.
- **`skills/wireframe/step-00-init.md`** — résout `wf_platform` (frame0 |
  penpot | none) et persiste dans l'état du skill. Step-02 lit le helper
  correspondant.
- **`skills/wireframe/step-02-design.md`** — flow rendu plateforme-agnostique
  (tableau de routing helper/export en tête, exemples par plateforme pour
  `export-png`).
- **Tests** : 60 nouveaux tests `tests/test-penpot-helper.sh` (validation
  args par action, descripteur MCP shape pour `execute_code`/`export_shape`,
  JS construction pour add-shapes, dry-run vs read-actions, format enum
  png|svg, rejet path relatif, config-driven format default). 60/60
  passing. Tests frame0 inchangés : 97/97 toujours OK.

### Changed — Wireframes export bypasses MCP via Frame0 HTTP API (breaking)

- **Pourquoi** : Frame0 MCP `export_page_as_image` retourne la PNG dans un
  bloc `image` content (base64 rendu visuellement par le harness Claude
  Code, jamais exposé en texte → impossible à piper vers un script). Le
  flow précédent (`export-page` MCP → `save-export` base64) ne pouvait pas
  fonctionner depuis le harness.
- **`frame0-helper.sh export-png`** (nouveau) — action **local-only**
  (jamais de descripteur MCP). POST direct à l'API HTTP de Frame0 desktop
  (`http://localhost:<api-port>/execute_command`, commande
  `file:export-image`), décode le `.data` base64 de la réponse, écrit le
  fichier nommé d'après `--output-path` (= `feature_slug-screen_id-state.png`
  depuis le skill `/wireframe`). Args : `--page-id`, `--output-path`,
  optionnels `--format=png|jpeg|webp`, `--api-port=N`. Exit 0 succès
  (`{written:true, bytes:N, mime, api_base}`), 1 si Frame0 desktop
  injoignable / API renvoie `success:false` / décode échoue, 2 args
  invalides.
- **`wireframes.frame0_api_port`** (nouveau, schema config) — port HTTP API
  Frame0 desktop. Défaut `58320` (= défaut Frame0). Override seulement si
  Frame0 lancé avec `--api-port=N`. Sub `wireframes.export_scale` ignoré
  par `export-png` (Frame0 HTTP API n'a pas de paramètre scale).
- **`frame0-helper.sh export-page`** — toujours présent mais **deprecated**
  pour usage depuis le harness Claude Code (header + usage le notent).
  Conservé pour usage librairie/manuel.
- **`frame0-helper.sh save-export`** — toujours présent (utile pour décoder
  un base64 arbitraire). Décrit comme outil général, plus comme étape du
  pipeline `/wireframe`.
- **`skills/wireframe/step-02-design.md`** — étapes 3+4 fusionnées en une
  seule étape `export-png`. Bloc `## Dry-run` mis à jour
  (`export-png --dry-run` retourne `{written:false}` sans hit HTTP).
- **Tests** : 14 nouveaux tests `export-png` (validation args, format enum
  png|jpeg|webp, port validation, dry-run, mock success/error/missing-data,
  HTTP unreachable, config-port resolution, jamais de descriptor MCP). Mock
  via `$SNAP_FRAME0_MOCK_RESPONSE_FILE` (hidden test stub). 97/97 passing.

### Removed — Wireframes export source dir

- **`wireframes.export_source_dir`** (schema config) — supprimé. La prémisse
  (Frame0 écrit dans un dossier OS unique type `~/Downloads`) était fausse :
  Frame0 retourne base64 via MCP, et la PNG arrive maintenant directement
  sur disque via `export-png`. Plus de `mv` depuis Downloads.
- **`frame0-helper.sh move-export`** — supprimé.
- Default-fill `wireframes.export_source_dir = "~/Downloads"` retiré de
  `load-config.sh`.

### Changed — Plugin agents namespacing (breaking)

- **Préfixage `snap-` sur tous les agents bundlés du plugin** pour éviter les
  collisions avec les `.claude/agents/` du projet utilisateur. Claude Code
  donne la priorité aux agents du projet sur ceux du plugin lorsque les noms
  collident — sans préfixe, un agent `developer.md` ou
  `code-reviewer-technical.md` du projet écrasait silencieusement l'agent
  bundlé.
  - `agents/developer.md` → `agents/snap-developer.md`
  - `agents/code-reviewer-technical.md` → `agents/snap-code-reviewer-technical.md`
  - `agents/code-reviewer-functional.md` → `agents/snap-code-reviewer-functional.md`
  - `agents/code-reviewer-security.md` → `agents/snap-code-reviewer-security.md`
  - `agents/code-reviewer-qa.md` → `agents/snap-code-reviewer-qa.md`
  - Frontmatter `name:` aligné sur le nouveau nom de fichier.
- Refs mises à jour dans `skills/develop/` (step-00-init, step-02-prepare,
  step-03a-standalone) et `skills/qa/` (step-02-interpret, step-03-fix,
  step-04-retrigger). Note : `step-04-retrigger` utilisait des noms
  pré-existants incorrects (`reviewer-technical` au lieu de
  `code-reviewer-technical`) — corrigé en passant.
- Doc mises à jour : `docs/skills/develop.md`, `docs/structure.md`,
  `docs/plugin.md`, `docs/diagram.md`, `docs/roadmap.md`,
  `_shared/templates/docs-defaults/wireframes-gallery.md`.
- **Override utilisateur** : un projet qui veut surcharger un agent du plugin
  peut créer `.claude/agents/snap-<name>.md` (la priorité project > plugin
  reste effective sur le nom préfixé).

### Added — Templates customization

- **Système de templates customisables** — section `templates` dans
  `snapship.config.json` permet override par catégorie sans toucher au plugin
  (cf. `docs/templates.md`).
  - Schémas: `templates.tickets.{user_story,bug,epic}`,
    `templates.pr`, `templates.review_thread`, `templates.aggregated_feedback`
    (tous `string|null`, défaut `null` → bundlé).
  - Override relatif → résolu depuis project root ; absolu → tel quel.
  - Override pointant vers fichier inexistant → `resolve-template.sh` exit 2
    (échec explicite, pas de fallback silencieux).
- `_shared/resolve-template.sh` — helper unique de résolution
  (kind=ticket|pr|review-thread|aggregated-feedback). User override > bundlé.
  Exit 0 succès | 1 args invalides | 2 fichier introuvable.
- `_shared/templates/` — réorganisation **breaking** (anciens chemins retirés) :
  - `tickets/{user-story,bug,epic}/{github,gitlab,jira}.md` (9 templates,
    matrice type × plateforme)
  - `pr/{github,gitlab,default}.md`
  - `review-thread/{github,gitlab,jira}.md`
  - `aggregated-feedback.md` (blob interne fix-loop)
- `tickets-adapter.sh comment-pr` — nouvelle action pour poster un commentaire
  sur PR/MR (github via `gh pr comment`, gitlab via `glab mr note`). Args
  `--pr-id` + (`--comment` | `--body-file=PATH`). JIRA renvoie
  `{ok:false, error:"not_supported"}` exit 1 (pas de PR concept).
- `/ticket step-03-enrich` — classification heuristique du type ticket
  (`user-story` par défaut, `bug` si keywords/scope match, `epic` si agrège
  ≥3 child stories). Persisté sur chaque story pour pickup par step-04-format.
- `/ticket step-04-format` — résolution template par story via
  `resolve-template.sh --kind=ticket --type=$story_type --platform=$platform`.
- `/develop step-04-sync` — section C "Post review thread (best-effort)" :
  rendu via `templates.review_thread` resolved + posté via `comment-pr`.
- `/develop step-03a-standalone` — `aggregated_feedback` (injection dev
  fix-loop) rendu via `templates.aggregated_feedback` resolved.
- Tests :
  - `tests/test-resolve-template.sh` (25 assertions, 7 sections — args,
    bundled fallback × kinds, override ticket/pr/review-thread/agg, absolute
    path, missing file, null override).
  - Extension `test-load-config.sh` ([13]-[15] templates defaults injection +
    user override préservé + schema rejection).
  - Extension `test-tickets-adapter.sh` ([29]-[36] comment-pr dry-run, github
    via mock gh `pr comment`, gitlab via mock glab `mr note`, jira
    not_supported, missing pr-id / comment / body-file, no MCP descriptor
    leak).
  - Fixtures `tests/fixtures/valid/templates/` (5 templates custom),
    `tests/fixtures/invalid/config/bad-templates.json` (rejet schema).

### Removed — Templates customization (breaking)

- Champ `repository.pr_template_path` retiré (remplacé par `templates.pr`).
- Champs `documentation.templates.prd_global` /
  `documentation.page_naming.prd_global` retirés (alignés sur removal v0.2 du
  template `prd-global.md`).
- Anciens templates plats `_shared/templates/ticket-{platform}.md` et
  `_shared/templates/pr-default.md` supprimés (remplacés par layout
  hiérarchique `tickets/{type}/{platform}.md` et `pr/{platform}.md`).

### Added (v0.2 — breaking)

- **Doc architecture refactor** — PRD = archive immuable, doc fonctionnelle = source vivante (cf. `docs/docs-architecture.md`).
  - PRD path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (figé post-ship, tags domaines).
  - Doc fonctionnelle: arbre `{functional_root}/{domain}/{journey}` (mise à jour incrémentale post-QA).
- `/snap:doc-import` skill — bootstrap d'un projet existant: import doc legacy AFFiNE/Notion, classification `lookup-or-create-page` `{domain}/{journey}`, hydrate `domains.json`. 6 steps (init/discover/classify/normalize/publish/finish), cache éphémère `.doc-import-cache/`.
- `/snap:doc-update` skill — propage l'état post-QA aux pages fonctionnelles impactées. Modes `diff` (patch sections impactées) ou `rewrite` (regénération complète, override auto si page vide). 5 steps (init/collect/update/publish/finish), prompts AI "describe end state, never reference PRD/tickets/git". Auto-trigger via `SNAP_NEXT_SKILL=` post-QA.
- `domains.schema.json` + `_shared/domains-state.sh` — CRUD persistant `.claude/product/domains.json` (source de vérité ID pour idempotent `lookup-or-create`). Subcommands: init, add-domain, add-journey, get-domain, get-journey, list-domains, list-journeys, has-domain, has-journey, validate (ajv).
- `docs-adapter.sh` — 5 nouvelles actions write idempotent: `lookup-page`, `lookup-or-create-page`, `update-page-content`, `set-page-tags`, `create-page-tree`. Émission MCP descriptor (exit 10), `--dry-run` short-circuit writes seulement.
- `/snap:define` step-05-publish — pousse PRD archive (`{YYYY}/{MM-YYYY}/{NN-feature}` via `create-page-tree` + `apply-template`) ET garantit `lookup-or-create-page` pour chaque `{domain}/{journey}` impacté. Met à jour `domains.json`.
- `/snap:qa` step-05-finish — rollup `feature.state → qa-validated` quand tous tickets validés (mutation jq + ajv-validate post). Auto-trigger `/snap:doc-update` via `SNAP_NEXT_SKILL=doc-update --feature=${id} -a` si `documentation.auto_update_on_qa_success: true` (gated par flag `--no-doc-update`).
- Config additions: `documentation.paths.{functional_root,prd_root}`, `documentation.auto_update_mode` (`diff|rewrite`), `documentation.auto_update_on_qa_success` (bool). Defaults injectés via `load-config.sh` (deep-merge).
- Fixtures v0.2: `tests/fixtures/valid/meta/{full,v02-defined}.json`, `valid/domains/{empty,full}.json`, `invalid/meta/{bad-domain-slug,legacy-affine-field}.json`, `invalid/domains/{missing-page-id,journey-missing-page-id}.json`.
- Tests: `tests/test-domains-state.sh` (22 assertions, 8 sections — idempotence add-domain preserves journeys, ajv validate). Extension `test-docs-adapter.sh` (+ assertions [25]-[33] couvrant 5 actions v0.2 + dry-run write-only). Extension `test-load-config.sh` ([10]-[12] paths defaults injection + override préservé incluant `auto_update_on_qa_success: false`). `validate-schemas.sh` étend à `domains/`.

### Changed (v0.2 — breaking)

- `meta.json` — schema breaking: drop `affine_page_id`, `affine_url`, `affine_wireframes_page_id`. Ajoute `domains: [string]`, `impacted_journeys: [{domain, journey_slug}]`, `prd: {page_id, url, path}`. `additionalProperties: false` rejette désormais les anciens champs.
- `/snap:ticket` step-01-load — lit `prd.page_id` / `prd.url` (au lieu des legacy `affine_*`).
- Templates docs — `prd-feature.md` étendu (variables change-request complètes: `feature_status`, `target_release`, `solution_overview`, `in_scope`/`out_of_scope`, blocs `acceptance_criteria`, `user_segments`, `edge_cases`, `error_states`, `wireframes`, `tickets`, `open_questions`).

### Removed (v0.2 — breaking)

- Template `prd-global.md` retiré — la "global PRD" est remplacée par les domain pages générées idempotemment via `lookup-or-create-page` (`/snap:doc-import` ou `/snap:define` publish).
- Champs `meta.json.affine_*` (cf. Changed). Pas de migration — v0.1 = pilote dogfood seul.

### Fixed

- `load-config.sh` — bug deep-merge defaults: `// null` traitait `false` comme null, écrasait l'override user explicite (`auto_update_on_qa_success: false` revertait à `true`). Fix: `if (.documentation | has("key")) | not then` (pattern aligné sur le block `paths`). Test `test-load-config 12.4` couvre la régression.

### Added

- Plugin manifest at `.claude-plugin/plugin.json` (Claude Code schema-conforme).
- `.mcp.json` racine bundle `code-review-graph` MCP — auto-start quand plugin activé.
- `NOTICE` documentant attributions community MCPs (code-review-graph, affine-mcp-server, frame0-mcp-server, playwright-mcp).
- `/snap:init` skill: bootstrap workspace (config wizard + scaffold `.claude/product/`). Détection MCP/git, AskUserQuestion drive, autonomous mode (`-a`), `--force` overwrite.
- `/qa` skill complet: pipeline 6 étapes (init→collect→interpret→fix→retrigger→finish), regression scope=impacted via code-review-graph (fallback tests-only), wireframe diff Playwright vs Frame0 PNG, code-reviewer-qa agent, dev↔qa cycle bounded, opt-in retrigger des 3 reviewers /develop.
- `/develop` skill complet: standalone + loop session/daemon, 3 reviewers parallèles (technical/functional/security), atomic commits, fail_strategy (next-ticket/stop/retry+fallback).
- `/wireframe` skill complet: filtre UI tickets, génération multi-écrans Frame0, AFFiNE gallery embed.
- `/ticket` skill complet: décomposition PRD → tickets, enrichissement explore-codebase, push plateforme adapter (github/gitlab/jira).
- `/define` skill complet: setup wizard initial, brainstorm PRD interactif, AFFiNE storage.
- 4 reviewer agents: technical, functional, security, qa.
- E2E tests: define, ticket, wireframe, develop, qa (135 deterministic checks).

### Changed

- `tickets.json` schema étendu pour cycle /qa: status enum + `qa-validated`, `acceptance_criteria.ac_id`, `qa_cycles_used`, `qa_last_severity`, `qa_last_flaky_verdict`, `qa_blocked`, `qa_retriggered`, `qa_retrigger_severity`, `qa_retrigger_verdicts`, `updated_at`.
- `/define` ne crée plus `snapship.config.json` — responsabilité déplacée vers `/snap:init`. Tous les skills (define/ticket/wireframe/develop/qa) exit early avec pointer vers `/snap:init` si config absente.
- `setup-config.sh --write` génère maintenant `$schema` avec URL github raw (portable cross-installs) au lieu d'un chemin relatif au plugin (cassé une fois plugin installé hors repo).

### Removed

- Legacy `plugin.json` racine remplacé par `.claude-plugin/plugin.json`.
- Champs custom invalides (`skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path`, `commands` array d'objets, `mcp_servers`) — non supportés par schéma plugin CC.

## [0.1.0] — TBD

Premier scaffold pré-marketplace. Cible: validation interne projet pilote (Phase 8 dogfooding) avant publication marketplace `bryanberger/claude-plugins`.
