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
| Workspace AFFiNE      | 1 par projet code, mappé via `artysan.config.json` (`documentation.workspace`)                                                      |
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
| Config                | `artysan.config.json` racine projet (étend defaults bundlés)                                                                        |
| Auth                  | Aucune dans config — MCP/CLI gèrent (gh auth, glab auth, $AFFINE_API_TOKEN)                                                         |
| Sections config       | `repository`, `tickets`, `documentation`, `wireframes`, `testing`, `naming`, `ai`, `develop`, `qa`, `lifecycle_scripts`, `defaults` |

## Décisions design (history résolution issues)

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

**Choix:** plugin v1 packagé via `plugin.json`. Install marketplace CC ou clone manuel → paths officiels `~/.claude/skills/` + `~/.claude/agents/` (ou projet `.claude/`). Pas de symlink custom.

### `merge_method` config

**Issue:** champ `merge_method` (squash/rebase/merge) non utilisé v1.

**Choix:** dropé. User merge PR manuellement post-création.

### Fixtures v1

**Choix:** skip fixtures v1. Pas de directory bundlé examples.

### Wireframe diff (QA)

**Choix:** Structural-diff (Frame0 MCP shapes ↔ Playwright DOM) plutôt que pixel-diff. Comparaison structure (count buttons/inputs/sections matchent, labels présents).

### CC optimizations appliquées

1. **Agent tool parallel** — review cycle `/develop` Phase 2 spawn 3 reviewers via 1 message N Agent calls (= parallel native CC, context isolé par fork)
2. **SessionStart hook opt-in** — pre-load config via template `session-start-hook.sh.tpl` + entry settings.json user
3. **`/usage` + `/cost`** — recommandés step-finish pour monitoring conso
4. **Telemetry NDJSON** — `_shared/telemetry.log` append-only avec rotation 10MB
5. **`--dry-run` global** — preview write ops sans toucher prod (combinable `-a`)

## Décisions validation (avant build)

1. **Plan validé** ✅
2. **Order build:** `/define` → `/ticket` → `/wireframe` → `/develop` → `/qa`
3. **Skills/agents location:** plugin v1 packagé via `plugin.json`. Install marketplace CC ou clone manuel → paths officiels `~/.claude/skills/` + `~/.claude/agents/` (ou projet `.claude/`). Pas de symlink custom.
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
