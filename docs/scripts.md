# Scripts partagés `_shared/`

Tous scripts dans `skills/_shared/`. Réutilisables transverses.

## detect-platforms.sh

```bash
# args: --section=tickets|documentation|wireframes|all
# Output JSON: { tickets: { platform, via, auth }, documentation: {...}, ... }
# 1. Read snapship.config.json (via load-config.sh)
# 2. Pour chaque platform configurée:
#    - MCP server actif? (parse claude_desktop_config / .claude/settings.json)
#    - Sinon CLI dispo? (which gh glab jira)
#    - Test auth: gh auth status / glab auth status / jira me
# 3. Cache résultat session (in-memory, pas disque — config = source de vérité)
# 4. Fail fast si platform configurée mais aucun via dispo
```

## frame0-helper.sh

```bash
# Vérifie MCP frame0-mcp-server actif
# Wrapper pour batch operations (créer page + shapes en chaîne)
```

## setup-product-dir.sh

```bash
# Init .claude/product/ idempotent
# Crée index.md, copie templates si absents
```

## update-index.sh

```bash
# args: feature_id, state (defined|ticketed|wireframed|developed|qa-validated)
# Update tableau dans index.md
```

## update-progress.sh

```bash
# args: feature_id, step_num, step_name, status
# Append progress.md de la feature
```

## load-config.sh

```bash
# Parse snapship.config.json + apply defaults bundlés + inheritance rules
# Output: JSON normalisé (tous champs résolus) sur stdout
# Cas:
#   - Config absent → returns defaults
#   - Section absente → fill avec defaults (skill décide si bloquant — voir setup trigger)
#   - inherit → résout (tickets.platform=inherit → repository.platform)
#   - testing.*_command absent → auto-detect (package.json scripts, Makefile, pyproject)
#   - naming.ticket_id_regex absent → pattern par platform
# Validation JSON Schema:
#   - Lit `_shared/schemas/config.schema.json` (ou `.claude/product/schemas/` si copié)
#   - Valide via `jq` + check basique OU `ajv-cli` si dispo
#   - Erreurs schema → exit 1 + chemin champ + raison
#   - Check `version` champ — incompatibilité majeure → instruction migration
# Warnings (stderr, non-bloquants):
#   - tickets.platform != "jira" + tickets.jira.* set
#     → "Section tickets.jira ignorée sur platform Y"
#   - lifecycle_scripts.<name> set vers script inexistant → "script X path invalide"
# Cache résolution dans .claude/product/.config-resolved.json (invalidé si mtime change)
```

## Setup trigger pattern (chaque skill step-00)

```
1. load-config.sh → cache résolution
2. Pour chaque section requise (selon Auto-discovery sections par étape):
   - Si section absente OU champs critiques manquants → bloque + lance:
     setup-config.sh --section=<name> --interactive
   - setup-config.sh:
     - AskUserQuestion mapping interactif champs requis
     - Auto-discovery sub-fields (workspace via MCP, templates par heuristique nom)
     - Persist snapship.config.json
     - Validate via load-config.sh schema
   - Skill reprend step-00 avec config complète
3. Si flag `-a` ET section absente → fail explicite (no AskUserQuestion en autonomous)
```

## run-lifecycle-script.sh

```bash
# Exécute un lifecycle_script CUSTOM workflow (≠ hook Claude Code natif).
# args: script_name (pre_define|post_ticket|...), context_json
# Lit config.lifecycle_scripts.<script_name>
# Si clé absente OU null → skip silencieux
# Si défini (string path) → exec script avec context_json sur stdin
# Capture exit code: non-zéro = stop workflow (ou warning si --no-fail-lifecycle)
```

## ask-or-default.sh

```bash
# Wrapper AskUserQuestion: shortcircuit en mode -a vers default explicite.
# args:
#   --auto-mode=true|false      (state {auto_mode})
#   --question-id=<id>          (label diagnostic — ex: "confirm-platform")
#   --question="<text>"         (texte tool AskUserQuestion si interactif)
#   --options=<csv>             (options possibles)
#   --default=<value>           (REQUIS si auto-mode=true)
# Comportement:
#   - auto-mode=true  → echo "{default}" sur stdout, exit 0
#   - auto-mode=true sans default → exit 1 + msg "auto-mode without default: question-id={id}"
#   - auto-mode=false → exit 0 + signal au skill d'invoquer AskUserQuestion tool natif
#                       (le wrapper ne peut PAS appeler le tool lui-même — skill orchestrera)
# Note: en mode interactif, le wrapper est un guard/validator. Le tool call reste skill-side.
```

## setup-config.sh

```bash
# Auto-générer snapship.config.json racine projet
# 1. Parse .git/config → repository.{http_url, ssh_url, platform}
# 2. Detect MCP servers actifs (affine, notion, frame0, atlassian, github, gitlab)
# 3. AskUserQuestion progressive par section:
#    - tickets: platform + url + (si JIRA: jira.project_key + jira.workflow_states/transitions)
#    - documentation: platform + workspace_id + root_page_id + templates mapping
#    - wireframes: confirm frame0 ou skip
#    - testing: auto-detect commands + AskUserQuestion override
#    - naming: defaults branch_pattern/commit_pattern + AskUserQuestion override
#    - develop: review_cycles_max + severity_threshold + fail_strategy
#    - qa: qa_cycles_max + severity_threshold + retrigger_review
#    - defaults: lang (FR/EN)
# 4. Write snapship.config.json
# Idempotent: si config existe, propose update sections incomplètes
```

## detect-test-commands.sh

```bash
# Auto-detect commandes testing/typecheck/lint/format
# Output JSON: { test_command, typecheck_command, lint_command, format_command }
# Heuristique:
#   - package.json scripts → "test", "typecheck", "lint", "format" (priorité)
#   - pnpm-lock.yaml → préfixe "pnpm", yarn.lock → "yarn", autre → "npm run"
#   - Cargo.toml → "cargo test", "cargo check", "cargo clippy", "cargo fmt"
#   - pyproject.toml → "pytest", "mypy", "ruff check", "ruff format"
#   - Makefile → cibles "test", "lint", etc. si présentes
#   - Sinon → null (skill prompt user)
```

## apply-naming.sh

```bash
# args: type (feature_id|branch|commit), context_json
# Lit config.naming.* + render template avec vars du context
# Vars supportées:
#   - feature_id: hardcoded NN-kebab — args: {nn} (numéro), {name} → kebab tronqué `feature_slug_max_length`
#   - branch: {type}, {ticket_id}, {slug}
#   - commit: {type}, {scope}, {message}
# Slugify automatique (kebab-case, ASCII fold, troncature)
```

## check-mcp-required.sh

```bash
# args: skill_name [--extra=<csv>]
# Lit config.ai.mcp_servers_required (fail-fast) + mcp_servers_optional (warn)
# --extra=<csv> ajoute MCPs dynamiquement à check-list required pour ce run
#   (ex: skill /qa appelle avec --extra=playwright si wireframe_check.enabled=true)
# Vérifie chaque MCP est actif (parse claude_desktop_config / .claude/settings.json)
# Required absent → exit 1 + install instructions
# Optional absent → log warning + features dépendantes désactivées (flag retourné via stdout JSON)
# Output stdout: { available: [...], missing_required: [...], missing_optional: [...] }
# Appelé par chaque skill step-00 avant de continuer
#
# Conflit name multiples (ex: 2 affine variants installés):
#   - Match regex pattern (`affine-mcp*` matche `affine-mcp-server` ET `affine-mcp-server-v2`)
#   - First-match deterministic (ordre alphabétique stable depuis JSON config)
#   - Si N>1 match → stderr warning: "Multiple MCP match 'affine-mcp*': [name1, name2]. Using: name1."
#   - User peut forcer name exact dans config (`mcp_servers_required: ["affine-mcp-server"]` strict)
```

## docs-adapter.sh (abstraction AFFiNE/Notion)

```bash
# Route vers MCP selon config.documentation.platform
# Actions (lecture):
#   - get <page_id>                        → markdown content
#   - search <query>
#   - lookup-page (--title) (--workspace-id|--parent-id)        → page_id|empty (v0.2)
# Actions (écriture):
#   - create <parent_id> <title> <md>      → page_id + url
#   - apply-template <tpl_id> <parent_id> <title> <vars_json> → page_id + url
#   - upload-blob <file_path>              → blob_id (pour embed images)
#   - update <page_id> <markdown>
#   - lookup-or-create-page (idempotent) → page_id (existing or new) (v0.2)
#   - update-page-content <page_id> <markdown>                  (v0.2)
#   - set-page-tags <page_id> <tags_json_array>                 (v0.2)
#   - create-page-tree <path=A/B/C> (--workspace-id|--parent-id)→ leaf page_id (v0.2)
# Implémentations:
#   - affine: appels MCP affine-mcp-server
#   - notion: appels MCP notion-mcp (community)
# Mode: les write actions sortent un MCP descriptor (exit 10) + court-circuitent en --dry-run.
```

## domains-state.sh (v0.2 — cache domain/journey ↔ page IDs)

```bash
# CRUD .claude/product/domains.json (persistant, schema: domains.schema.json)
# Source vérité ID pour idempotent lookup-or-create dans /snap:define publish + /snap:doc-update.
# Subcommands:
#   - init                                              → écrit {} si absent
#   - add-domain SLUG TITLE PAGE_ID [URL]               → idempotent (preserve journeys)
#   - add-journey DOMAIN_SLUG JOURNEY_SLUG TITLE PAGE_ID [URL]
#   - get-domain SLUG                                   → JSON entrée ou vide
#   - get-journey DOMAIN_SLUG JOURNEY_SLUG              → JSON entrée ou vide
#   - list-domains | list-journeys [DOMAIN_SLUG]
#   - has-domain SLUG | has-journey DOMAIN_SLUG SLUG    → exit 0/1
#   - validate                                          → ajv contre schema
```

## tickets-adapter.sh (abstraction GitHub/GitLab/JIRA)

```bash
# Route vers MCP > CLI selon config.tickets.platform
# Actions:
#   - create <ticket_json>                 → id + url
#   - get <id>                             → ticket_json
#   - update <id> <fields_json>
#   - comment <id> <text>                          (commente un ticket/issue)
#   - comment-pr --pr-id=N (--comment | --body-file=PATH) (github/gitlab uniquement —
#                                                  jira renvoie not_supported exit 1)
#   - list <feature_query>                 → array
#   - list-prs --branch=<name>             → existant PR pour la branche (idempotent push)
#   - update-pr / create-pr                → CRUD PR
# Implémentations:
#   - github: gh CLI ou MCP github
#   - gitlab: glab CLI ou MCP gitlab
#   - jira: jira CLI ou MCP atlassian
# --body-file: lu dans COMMENT_TEXT si --comment vide (utile pour rendered review-thread).
```

## resolve-template.sh

```bash
# Résout chemin template (user override > bundlé). Sortie: chemin absolu sur stdout.
# args:
#   --kind=ticket|pr|review-thread|aggregated-feedback (REQUIS)
#   --type=user-story|bug|epic                          (REQUIS si kind=ticket)
#   --platform=github|gitlab|jira|default               (REQUIS pour ticket / pr / review-thread;
#                                                        pr accepte aussi 'default')
#   --project-root=PATH                                 (défaut: $PWD ou $SNAP_PROJECT_ROOT)
# Lecture: load-config.sh (--no-validate) → templates.<key> selon kind.
#   ticket           → templates.tickets.<type>     (user_story|bug|epic)
#   pr               → templates.pr
#   review-thread    → templates.review_thread
#   aggregated-feedback → templates.aggregated_feedback
# Override:
#   - non-null + chemin relatif → résolu depuis project-root
#   - non-null + chemin absolu  → tel quel
#   - non-null + fichier absent → exit 2 (échec explicite)
#   - null/absent               → fallback bundlé `_shared/templates/...`
#   - bundlé absent             → exit 2
# Exit codes: 0 succès | 1 args invalides | 2 fichier introuvable
```

## telemetry.sh

```bash
# Append NDJSON event à _shared/telemetry.log
# args: --skill=<name> --step=<id> --status=<ok|fail|skip|retry> --duration-ms=<n> [--ticket=<id>] [--cycle=<n>] [--severity=<level>]
# Format ligne: {"ts":"...","skill":"...","step":"...","duration_ms":...,"status":"...",...}
# Rotation auto > 10MB (renomme .1, garde 2 fichiers max)
# Gitignored
```
