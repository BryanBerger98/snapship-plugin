# Décisions

## Décisions validées (config workflow)

| Décision              | Choix                                                                                                                               |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Architecture          | 5 skills indépendants chaînables, workflow inline                                                                                   |
| Slash commands        | `/define`, `/ticket`, `/wireframe`, `/develop`, `/qa`                                                                               |
| Plateformes tickets   | Hybride MCP-first → CLI fallback (gh/glab/jira)                                                                                     |
| Frame0                | MCP `frame0-mcp-server` (28 tools dispo)                                                                                            |
| AFFiNE                | MCP `affine-mcp-server` (DAWNCR0W, 84 tools) — source primaire docs produit                                                         |
| Templates docs        | Pages templates natives AFFiNE (UI), référencées par template_id                                                                    |
| Pages AFFiNE générées | PRD global, PRD feature, Wireframes gallery feature                                                                                 |
| Workspace AFFiNE      | 1 par projet code, mappé via `snapship.config.json` (`documentation.workspace`)                                                      |
| Source vérité PRD     | AFFiNE (primaire) — local minimal                                                                                                   |
| Source vérité tickets | Plateforme primary, cache local                                                                                                     |
| Stockage local        | `.claude/product/` minimal (cache + progress + meta)                                                                                |
| PRD                   | Global + mini-PRD par feature (sur AFFiNE)                                                                                          |
| Wireframes            | Par feature, multi-écrans (Frame0 + gallery AFFiNE)                                                                                 |
| Tickets format        | Adaptatif par plateforme                                                                                                            |
| Langue                | Français                                                                                                                            |
| Mode                  | Interactif par défaut, `-a` autonome                                                                                                |
| Resume                | `-r` partout                                                                                                                        |
| Existing project      | Auto-detect + discovery                                                                                                             |
| `/develop`            | Standalone (1 ticket = 1 cycle dev/review) + `--loop=session\|daemon` (epic/feature)                                                |
| Chaining              | Manuel (suggestion fin de skill)                                                                                                    |
| Sync tickets          | Draft local → review batch → push                                                                                                   |
| Config                | `snapship.config.json` racine projet (étend defaults bundlés)                                                                        |
| Auth                  | Aucune dans config — MCP/CLI gèrent (gh auth, glab auth, $AFFINE_API_TOKEN)                                                         |
| Sections config       | `repository`, `tickets`, `documentation`, `wireframes`, `testing`, `naming`, `ai`, `develop`, `qa`, `lifecycle_scripts`, `defaults` |

## Décisions design (history résolution issues)

### Bootstrap config: skill dédié `/snap:init`

**Issue:** `/define` portait à la fois la création de `snapship.config.json` et la définition produit. Conséquences: step-00 surchargé, échec silencieux quand `load-config.sh` traitait config absente comme `{}` (pas de fail-fast), couplage init ↔ entrée workflow PRD.

**Choix:** extraction dans skill dédié `/snap:init` (steps `step-00-detect.md` + `step-01-write.md`). Toutes les autres skills (define/ticket/wireframe/develop/qa) exit early avec `ERROR: snapship.config.json not found. Run /snap:init first.` si config absente.

**Why:** séparation responsabilités, fail-fast loud > silent fallback, init explicite (1× par projet).

**How to apply:** ajouter un nouveau skill = ajouter le guard `[ -f "$PWD/snapship.config.json" ] || exit 1` au début de step-00.

### `$schema` config: github raw URL

**Issue:** `setup-config.sh --write` injectait `"$schema": "./skills/_shared/schemas/config.schema.json"` (chemin relatif au project root). Une fois le plugin installé via marketplace, le fichier schéma vit dans le cache CC, pas dans le projet → IDE schema validation cassée.

**Choix:** URL github raw `https://raw.githubusercontent.com/BryanBerger98/snapship-plugin/main/skills/_shared/schemas/config.schema.json` (résolu par tout IDE une fois le repo public).

**Why:** portabilité cross-install. Runtime `load-config.sh` lit toujours le schema depuis le bundle plugin (pas via le champ `$schema`), donc validation ajv non impactée.

### feature_id_pattern

**Issue:** `/define` crée feature avant tickets exister → pattern `{ticket_id}-{feature_slug}` impossible.

**Choix:** **Option B** — `feature_id` toujours `NN-kebab` (decouple). `ticket_id` séparé, utilisé seulement dans `branch_pattern`/`commit_pattern`.

**Why:** simple, indépendant plateforme. Découplage feature ↔ tickets.

### JIRA-only fields

**Issue:** champs `project_key`, `workflow_states`, `transitions`, `epic_link_field`, `estimation_field` JIRA-only mélangés au top-level `tickets`.

**Choix:** nester sous `tickets.jira.*`. Warning stderr si `platform != "jira"` ET `tickets.jira.*` set.

### `hooks` vs `lifecycle_scripts`

**Issue:** collision sémantique avec hooks Claude Code natifs (`SessionStart`, `PreToolUse`).

**Choix:** rename config key + script file:

- `config.hooks` → `config.lifecycle_scripts`
- `_shared/run-hook.sh` → `_shared/run-lifecycle-script.sh`
- Flag `--no-fail-hooks` → `--no-fail-lifecycle`

**Why:** clarté workflow vs CC natif.

### Distribution plugin v1

**Issue:** symlink convention `~/.agents/` non-officielle.

**Choix:** plugin v1 packagé via `.claude-plugin/plugin.json` (schema CC officiel). Install marketplace CC ou clone manuel → paths officiels `~/.claude/skills/` + `~/.claude/agents/` (ou projet `.claude/`). Pas de symlink custom.

### `merge_method` config

**Issue:** champ `merge_method` (squash/rebase/merge) non utilisé v1.

**Choix:** dropé. User merge PR manuellement post-création.

### Fixtures v1

**Choix:** skip fixtures v1. Pas de directory bundlé examples.

### Wireframe diff (QA)

**Choix:** Structural-diff (Frame0 MCP shapes ↔ Playwright DOM) plutôt que pixel-diff. Comparaison structure (count buttons/inputs/sections matchent, labels présents).

### Documentation: PRD archive vs doc fonctionnelle vivante (v0.2)

**Issue:** v0.1 traite tout en pages plates AFFiNE — 1 PRD global + 1 PRD par feature. Pas de séparation entre intention de changement (PRD éphémère) et état courant du produit (doc fonctionnelle vivante). Liens entre pages cassés en pratique. Pas de chemin configurable.

**Choix:** refonte v0.2 — deux types de pages distincts:
- **PRD / Change request** — archive immuable d'une évolution. Path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`. Tags = domaines impactés. Figée post-ship.
- **Doc fonctionnelle** — spec vivante hiérarchie `{functional_root}/{domain}/{user journey}`. Updated chaque ship via nouveau skill `/snap:doc-update`.

**Why:** PRD = "ce qu'on va changer" (forward-looking, périmé post-ship). Doc fonctionnelle = "ce que le produit fait aujourd'hui" (source vérité courante). Les mélanger pollue les deux usages.

**How to apply:** spec complète dans `docs/docs-architecture.md`. Breaking change vs v0.1, pas de migration (pilote uniquement).

### Doc fonctionnelle: structure domain → journey

**Choix:** hiérarchie 2 niveaux:
- Domain page (`auth`, `dashboard`) = overview + liens vers journeys
- User journey page (`Login Flow`, `Signup Flow`) = spec vivante détaillée

**Pas de log modifications sur domain page** — éviterait bloat exponentiel sur projets longs. Historique = via les pages PRD elles-mêmes (filtrables AFFiNE par tag + date).

**Pas de lien direct journey → PRD** — journey reste spec propre, PRD = archive externe.

### Doc legacy bootstrap: skill `/snap:doc-import`

**Issue:** projet existant avec doc AFFiNE accumulée libre/scattered ne respecte pas hiérarchie snap. Bootstrap manuel = friction majeure.

**Choix:** skill `/snap:doc-import` lit pages AFFiNE existantes → AI propose découpage domains/journeys → user confirme → restructure selon stratégie:
- `synthesize` (default): AI consolide N pages source → 1 journey doc
- `copy`: duplique vers snap path, archive originaux
- `move`: relocate pages source vers snap path

**Why:** doc legacy = courant. Sans bootstrap automatisé, plugin inutilisable sur projets existants.

**How to apply:** skill séparé de `/snap:define` (bootstrap one-shot vs cycle dev). PAS de migration v0.1 → v0.2 (pilote uniquement). PAS d'équivalent local-source (drop `doc-rebuild` proposé initialement).

### Auto-update doc post-ship

**Choix:** skill `/snap:doc-update` standalone, trigger:
- Auto post-`/snap:qa` si `documentation.auto_update_on_qa_success: true`
- Manuel `/snap:doc-update --feature=NN`

Mode update configurable: `diff` (default — patch sections impactées) ou `rewrite` (regenerate full journey doc). PRD jamais touché par cette skill.

### Slug vs titre

**Choix:** page AFFiNE = titre humain ("Login Flow"). Cache interne `domains.json` = slug kebab (`login-flow`) pour mapping. User saisit titre, slug auto-généré (override possible).

### CC optimizations appliquées

1. **Agent tool parallel** — review cycle `/develop` Phase 2 spawn 3 reviewers via 1 message N Agent calls (= parallel native CC, context isolé par fork)
2. **SessionStart hook opt-in** — pre-load config via template `session-start-hook.sh.tpl` + entry settings.json user
3. **`/usage` + `/cost`** — recommandés step-finish pour monitoring conso
4. **Telemetry NDJSON** — `_shared/telemetry.log` append-only avec rotation 10MB
5. **`--dry-run` global** — preview write ops sans toucher prod (combinable `-a`)

## Décisions validation (avant build)

1. **Plan validé** ✅
2. **Order build:** `/define` → `/ticket` → `/wireframe` → `/develop` → `/qa`
3. **Skills/agents location:** plugin v1 packagé via `.claude-plugin/plugin.json` (schema CC officiel). Install marketplace CC ou clone manuel → paths officiels `~/.claude/skills/` + `~/.claude/agents/` (ou projet `.claude/`). Pas de symlink custom.
4. **Templates docs-defaults:** bundlés dans `_shared/templates/docs-defaults/` (push opt-in via setup)

## Drop list (non retenu v1)

- `epic_link_field`, `estimation_field`, `ci_provider`, `coverage_threshold` — config menteuse
- `test_folder_name`, `test_files_pattern`, `storage.product_dir` — jamais lus
- Hooks mid-step (gardé seulement pre/post skill via `lifecycle_scripts`)
- Symlink `~/.agents/` convention
- Auto-merge PR côté skill
- `merge_method` config field

## Patterns inline (pas dépendance externe)

Workflow autonome. Patterns natifs:

**Progressive workflow:**

- Step loading via frontmatter `next_step` (1 step = 1 fichier MD)
- State variables persistés entre steps (`progress.md` + `meta.json`)
- Save mode + templates + scripts `_shared/`
- Resume `-r {task-id}` avec partial match
- Self-validation typecheck/lint/test post-execution

**UX & flags:**

- Flag system (lowercase enable, uppercase disable)
- AskUserQuestion à chaque phase clé (avec wrapper `ask-or-default.sh` pour `-a` autonomous)
- Menus Accept/Plan/Cancel sur sorties intermédiaires
- Brainstorm interactif avec parallel exploration

**Exécution:**

- Parallel agents 1-10 selon complexité
- Stories atomiques 5-30min (1 ticket = 1 commit atomique)
- Branch naming configurable via `naming.branch_pattern`
- Daemon loop = setup-only (génère script, user lance — jamais auto-launch)
