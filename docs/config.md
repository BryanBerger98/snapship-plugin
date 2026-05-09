# Config — `artysan.config.json`

**Localisation:** racine projet (committable, partagée avec équipe).

**Sections:** `repository`, `tickets`, `documentation`, `wireframes`, `testing`, `naming`, `ai`, `develop`, `qa`, `lifecycle_scripts`, `defaults`.

## Schéma complet

```jsonc
{
  "$schema": "./.claude/product/schemas/config.schema.json",
  "version": "1.0",
  // setup-config.sh copie schemas bundlés `_shared/schemas/*.schema.json` → `.claude/product/schemas/` au premier run
  // load-config.sh valide config contre schema (Ajv ou jsonschema CLI). Fail explicite si invalide.
  "repository": {
    "platform": "github",                  // github | gitlab
    "http_url": "https://github.com/org/repo.git",
    "ssh_url": "git@github.com:org/repo.git",
    "default_branch": "main",
    "protected_branches": ["main", "develop"],   // refuse commit/push direct
    "pr_template_path": ".github/pull_request_template.md"
    // merge_method dropé v1 — user merge PR manuellement post-création
  },
  "tickets": {
    "platform": "jira",                    // github | gitlab | jira | inherit
    "url": "https://company.atlassian.net/browse/PROJ",
    "default_labels": ["artysan"],
    "jira": {                              // section utilisée seulement si platform=jira
      "project_key": "PROJ",
      "default_issue_type": "Story",
      "workflow_states": {                  // mapping états plateforme
        "todo": "To Do",
        "in_progress": "In Progress",
        "review": "In Review",
        "done": "Done"
      },
      "transitions": {                      // noms transitions JIRA
        "start": "Start Progress",
        "review": "Submit for Review",
        "complete": "Done"
      }
    }
  },
  "documentation": {
    "platform": "affine",                  // affine | notion
    "url": "https://app.affine.pro",
    "workspace": {
      "id": "ws-abc",
      "root_page_id": "page-xyz"
    },
    "templates": {
      "prd_global": "tpl-id-1",
      "prd_feature": "tpl-id-2",
      "wireframes_gallery": "tpl-id-3"
    },
    "auto_publish": true,                  // publish vs draft
    "page_naming": {
      "prd_global": "PRD - {product_name}",
      "prd_feature": "{feature_id} - {feature_name}",
      "wireframes_gallery": "Wireframes - {feature_name}"
    }
  },
  "wireframes": {                          // optionnel, absent = /wireframe désactivé
    "platform": "frame0",                  // frame0 (seul supporté)
    "export_format": "png",                // png | svg | pdf
    "export_scale": 2,                     // 1x, 2x, 3x (retina)
    "naming_pattern": "{feature_id}-{screen_name}"
  },
  "testing": {
    "test_command": "pnpm test",
    "typecheck_command": "pnpm typecheck",
    "lint_command": "pnpm lint",
    "format_command": "pnpm format"
  },
  "naming": {
    // feature_id format hardcoded: NN-kebab (ex: 01-auth) — pas configurable
    "feature_slug_max_length": 40,         // troncature slug
    "branch_pattern": "{type}/{ticket_id}-{slug}",
    "commit_pattern": "{type}({scope}): {message}",
    "ticket_id_regex": "[A-Z]+-[0-9]+"     // extract ID depuis branch/commit
  },
  "ai": {
    "max_parallel_agents": 5,
    "mcp_servers_required": [              // fail-fast au startup si absent
      "affine-mcp-server",
      "frame0-mcp-server"
    ],
    "mcp_servers_optional": [              // log-warn si absent, skill consulte runtime pour activer features
      "code-review-graph",                 // QA régression scope=impacted (fallback tests-only si absent)
      "playwright"                         // wireframe_check (skill /qa ajoute dynamiquement à check-list si qa.wireframe_check.enabled=true)
    ]
  },
  "develop": {
    "review_cycles_max": 3,                // max ping-pong review↔developer
    "auto_apply_review_feedback": true,    // dev applique feedback auto sans confirm
    "fail_strategy": "next-ticket",        // next-ticket|stop|retry — si max cycles atteint sans approval
    "reviews": {                           // 3 reviews spécialisées (parallèles, statiques sur diff)
      "technical": {
        "severity_threshold": "minor"      // info|minor|major|critical — bloque si ≥ seuil
      },
      "functional": {
        "severity_threshold": "minor"      // AC non remplis = major par défaut
      },
      "security": {
        "severity_threshold": "info"       // strict — bloque sur tout sauf clean
      }
    }
    // Désactivation par type runtime: flags --no-tech / --no-functional / --no-security
  },
  "qa": {
    "qa_cycles_max": 2,                    // ping-pong QA↔dev (indépendant review cycle /develop)
    "auto_apply_qa_feedback": true,        // dev applique fixes auto sans confirm
    "severity_threshold": "minor",         // info|minor|major|critical — bloque exit Phase QA si ≥ seuil
    "retrigger_review": false,             // si true ET fixes appliqués: re-run 3 reviewers /develop sur diff post-QA
    "regression": {
      "enabled": true,
      "scope": "impacted"                  // impacted (via code-review-graph MCP) | full | tests-only
    },
    "wireframe_check": {
      "enabled": false,                    // opt-in (setup Playwright requis)
      "mode": "playwright",                // playwright (seul mode supporté pour l'instant)
      "diff_threshold_pct": 5,             // % pixel diff toléré
      "severity_on_mismatch": "major"
    }
  },
  "lifecycle_scripts": {                   // scripts lifecycle CUSTOM (≠ hooks Claude Code)
    // ⚠️ Ces lifecycle_scripts sont DES SCRIPTS PROPRES À CE WORKFLOW.
    //    Ils ne sont PAS interprétés par Claude Code (pas dans events natifs
    //    SessionStart/PreToolUse/etc). Ils sont exécutés explicitement par
    //    chaque skill via _shared/run-lifecycle-script.sh aux moments lifecycle skill.
    // Définir uniquement scripts utiles. Clés absentes = skip implicite.
    // Scripts supportés: pre_define, post_define, pre_ticket, post_ticket,
    //                    pre_wireframe, post_wireframe, pre_develop, post_develop,
    //                    pre_qa, post_qa
    // Valeur = path script exécutable (recoit context JSON sur stdin).
    // Exemple:
    // "post_ticket": ".claude/lifecycle_scripts/notify-slack.sh"
  },
  "defaults": {
    "lang": "fr",                          // fr | en
    "auto_mode": false,
    "save_mode": true,
    "branch_mode": true,
    "economy_mode": false
  }
}
```

## Auth: ABSENTE

MCP/CLI gèrent indépendamment:

- `gh auth status`, `glab auth status`, `jira me`
- AFFiNE/Notion MCP servers utilisent leur propre config (`$AFFINE_API_TOKEN` env, etc.)
- Skill vérifie auth au runtime via `_shared/detect-platforms.sh`

## Règles de fallback

1. Config absente → defaults bundlés dans skill
2. Section absente → defaults section (sauf `documentation`/`tickets`/`testing` → setup interactif)
3. Champ absent → default ou inheritance:
   - `tickets.platform = "inherit"` → `= repository.platform`
   - `testing.*_command` absent → auto-detect via `package.json`/`pyproject.toml`/etc.
   - `repository.protected_branches` absent → `["main"]`
   - `naming.ticket_id_regex` absent → patterns par platform (JIRA: `[A-Z]+-[0-9]+`, GitHub: `#[0-9]+`)
   - `naming.feature_slug_max_length` absent → 40
   - `develop.review_cycles_max` absent → 3
   - `develop.reviews.{type}.severity_threshold` absent → `minor` (sauf `security` → `info`)
   - `qa.qa_cycles_max` absent → `2`
   - `qa.severity_threshold` absent → `minor`
   - `qa.retrigger_review` absent → `false`
   - `qa.regression.scope` absent → `impacted` (fallback `tests-only` si code-review-graph MCP absent)
   - `qa.wireframe_check.enabled` absent → `false` (opt-in)
4. **`feature_id` format hardcoded:** `NN-kebab` (ex: `01-auth`). `NN` = numéro auto-incrémenté depuis `index.md`, `kebab` = slugify nom feature tronqué à `feature_slug_max_length`.
5. Override CLI flag toujours prioritaire (`--platform=...`, `--review-cycles=N`)
6. `ai.mcp_servers_required` validé au startup chaque skill — fail fast si absent
7. `ai.mcp_servers_optional` validé au startup — log warning si absent, features dépendantes auto-désactivées (ex: code-review-graph absent → `qa.regression.scope` forcé `tests-only`)

## Auto-génération premier run

1. `_shared/setup-config.sh` lance si `artysan.config.json` absent
2. Parse `.git/config` → extract remote URL → detect repo platform + URLs
3. Tente MCP servers actifs → propose match (atlassian, github, notion, affine, frame0)
4. AskUserQuestion mapping pour ambigus + champs critiques (jira.project_key si JIRA, workspace_id, root_page_id, template_ids)
5. Génère `artysan.config.json` avec sections détectées
6. User peut éditer ensuite (config = source de vérité, pas re-détection)

## Auto-discovery sections par étape

| Skill        | Sections requises                                       | Si absent                      |
| ------------ | ------------------------------------------------------- | ------------------------------ |
| `/define`    | `documentation`, `ai`                                   | Setup interactif documentation |
| `/ticket`    | `tickets`, `repository`, `naming`                       | Setup interactif tickets       |
| `/wireframe` | `wireframes`, `documentation`                           | Erreur si `wireframes` absent  |
| `/develop`   | `repository`, `tickets`, `testing`, `naming`, `develop` | Setup interactif si manquant   |
| `/qa`        | `tickets`, `testing`, `qa`                              | Setup interactif si manquant   |

## Lifecycle scripts custom (≠ hooks Claude Code)

`pre_<skill>` exécuté avant step-00, `post_<skill>` après dernier step. Scripts supportés: `pre_define`, `post_define`, `pre_ticket`, `post_ticket`, `pre_wireframe`, `post_wireframe`, `pre_develop`, `post_develop`, `pre_qa`, `post_qa`.

Orchestrés explicitement par chaque skill via `_shared/run-lifecycle-script.sh` — scripts shell user, **pas** des hooks Claude Code natifs (qui eux opèrent au niveau session/tool: `SessionStart`, `PreToolUse`, etc.).

Skill passe contexte JSON via stdin (feature_id, ticket_ids, etc.).

## Validation runtime (JSON Schema)

`load-config.sh` valide config contre `_shared/schemas/config.schema.json`:

- Ajv ou `jq` + check basique
- Erreurs schema → exit 1 + chemin champ + raison
- Check `version` champ — incompatibilité majeure → instruction migration
- Warnings stderr non-bloquants:
  - `tickets.platform != "jira"` + `tickets.jira.*` set → "Section tickets.jira ignorée sur platform Y"
  - `lifecycle_scripts.<name>` set vers script inexistant → "script X path invalide"

Cache résolution dans `.claude/product/.config-resolved.json` (invalidé si mtime change).
