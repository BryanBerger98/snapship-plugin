# Templates

Le plugin résout les templates via `_shared/resolve-template.sh`, qui retourne
un objet JSON `{path, source, render_mode}`. Trois sources, dans l'ordre de
priorité :

1. **Override config** — chemin explicite dans `snapship.config.json` →
   `templates.*`. `render_mode=mustache`.
2. **Repo-native** — template markdown de l'hôte sous `.github`/`.gitlab`
   (`ISSUE_TEMPLATE`, `PULL_REQUEST_TEMPLATE`, `issue_templates`,
   `merge_request_templates`). Détecté par `_shared/detect-repo-templates.sh`,
   activé par `templates.use_repo_native` (défaut `true`). Concerne uniquement
   `ticket` et `pr` ; JIRA n'a pas de convention repo-native.
   `render_mode=scaffold`.
3. **Bundlé** — template par défaut sous `_shared/templates/`.
   `render_mode=mustache`.

`render_mode` indique au skill comment remplir le template :

- **`mustache`** → rendu variable par `_shared/render-template.sh` (placeholders
  `{{var}}` substitués depuis le contexte JSON).
- **`scaffold`** → le fichier est un squelette markdown statique (pas de
  placeholders). Le skill retire le frontmatter YAML éventuel, garde l'ordre des
  sections / checklists de l'équipe, et remplit chaque section depuis le
  contexte ticket/PR. Objectif : respecter le style maison du dépôt.

## Catalogue

| Kind | Type | Plateforme | Bundlé |
|------|------|-----------|--------|
| `ticket` | `user-story` | `github\|gitlab\|jira` | `_shared/templates/tickets/user-story/{platform}.md` |
| `ticket` | `bug` | `github\|gitlab\|jira` | `_shared/templates/tickets/bug/{platform}.md` |
| `ticket` | `epic` | `github\|gitlab\|jira` | `_shared/templates/tickets/epic/{platform}.md` |
| `pr` | — | `github\|gitlab\|default` | `_shared/templates/pr/{platform}.md` |
| `review-thread` | — | `github\|gitlab\|jira` | `_shared/templates/review-thread/{platform}.md` |
| `aggregated-feedback` | — | (pas de plateforme) | `_shared/templates/aggregated-feedback.md` |
| `docs-defaults/prd-feature` | — | (markdown standard) | `_shared/templates/docs-defaults/prd-feature.md` |
| `docs-defaults/wireframes-gallery` | — | (markdown standard) | `_shared/templates/docs-defaults/wireframes-gallery.md` |

> v0.1 `prd-global.md` retiré : la "global PRD" est remplacée par les domain
> pages générées idempotemment par `/snap:doc-import` ou `/snap:define`
> (étape publish).

## Templates repo-native (`.github` / `.gitlab`)

Quand `templates.use_repo_native` vaut `true` (défaut), `/ticket` et `/develop`
réutilisent les templates markdown déjà présents dans le dépôt avant de
retomber sur le bundlé. Conventions scannées (`detect-repo-templates.sh`) :

| Kind | Plateforme | Emplacements |
|------|-----------|--------------|
| `ticket` | `github` | `.github/ISSUE_TEMPLATE/*.md`, legacy `.github/ISSUE_TEMPLATE.md` |
| `ticket` | `gitlab` | `.gitlab/issue_templates/*.md` |
| `ticket` | `jira` | — (aucune convention repo-native) |
| `pr` | `github` | `.github/PULL_REQUEST_TEMPLATE.md` (+ racine, `docs/`, forme répertoire) |
| `pr` | `gitlab` | `.gitlab/merge_request_templates/*.md` |

Règles :

- **Markdown uniquement** — les formulaires d'issue YAML (`.yml`/`.yaml`) sont
  ignorés (le plugin ne parse pas les schémas de formulaire).
- **Mapping nom → type** : nom contenant `bug`/`defect` → `bug`, `epic` →
  `epic`, `story`/`feature` → `user-story`. Pas de correspondance → on retombe
  sur le legacy single-file (GitHub) ou le bundlé.
- **Forme répertoire PR** → préfère un fichier nommé `default.md`, sinon le
  premier par ordre alphabétique.
- `review-thread` et `aggregated-feedback` sont des artefacts internes snap :
  aucune convention repo-native, ils restent sur override config ou bundlé.
- `use_repo_native: false` → la couche repo-native est ignorée entièrement.

## Override utilisateur

Section `templates` dans `snapship.config.json` (tous les champs optionnels,
`null` par défaut) :

```json
{
  "templates": {
    "use_repo_native": true,
    "tickets": {
      "user_story": ".claude/templates/my-user-story.md",
      "bug":         null,
      "epic":        null
    },
    "pr":                 ".claude/templates/my-pr.md",
    "review_thread":      null,
    "aggregated_feedback": null
  }
}
```

Règles :

- **Chemin relatif** → résolu depuis la racine projet.
- **Chemin absolu** (`/...`) → utilisé tel quel.
- **Override absent ou `null`** → couche repo-native, puis fallback bundlé.
- **Override pointant vers un fichier inexistant** → `resolve-template.sh` exit 2
  (échec explicite, pas de fallback silencieux).
- **Un override explicite gagne toujours** sur le template repo-native.

Les overrides PR / review-thread / aggregated-feedback sont **uniques** (pas de
matrice par plateforme). Pour les tickets, l'override est par **type** ; le
type est classifié automatiquement par `/ticket` step-03 (bug / epic /
user-story par défaut), et la plateforme est déduite de
`tickets.platform` (le bundlé par plateforme reste le fallback si pas d'override).

## Variables disponibles

### Tickets — communes

`ticket_id`, `title`, `summary`, `feature_id`, `feature_title`, `epic_ref`,
`related_refs`, `labels`, `confidence`, `size`, contexte d'enrichissement
(`context.codebase`, `context.docs`, `context.web[]`).

### Tickets — `user-story`

`user_persona`, `user_goal`, `user_outcome`, `acceptance_criteria[]`,
`in_scope`, `out_of_scope`, `wireframes[]`, `technical_notes`, `test_unit`,
`test_integration`, `test_e2e`.

### Tickets — `bug`

`repro_steps[]`, `expected_behavior`, `actual_behavior`,
`environment_version`, `environment_runtime`, `environment_user_context`,
`acceptance_criteria[]`, `root_cause`, `regression_surfaces`,
`regression_tests`, `severity`, `frequency`, `first_seen`.

### Tickets — `epic`

`goal`, `success_metrics[]`, `in_scope`, `out_of_scope`, `child_stories[]`,
`acceptance_criteria[]`, `dependencies[]`, `risks[]`, `target_release`,
`epic_size`, `domain_pages`.

### PR

`feature_id`, `feature_title`, `branch`, `tickets[]` (liste des tickets
poussés), `summary`, `test_plan`, `breaking_changes`, `linked_prs[]`.

### Review thread (commentaire posté sur PR/MR/JIRA ticket)

`overall_severity`, `cycles_used`, `verdict`, `reviewers[]` (technical /
functional / security avec `severity`, `severity_threshold`, `blocking`,
`findings[]`), `cross_cutting`, `suggested_fix_order[]`.

### Aggregated feedback (interne, injecté au dev pour fix-loop)

Mêmes variables que `review-thread`, formatté pour consommation agent dev
(pas de markdown stylé heavy, focus sur findings actionables).

## Format-specific tweaks

- **GitHub** : `<details>` blocks pour le contexte (issue lisible), labels via
  body (mappés directement par `tickets-adapter.sh`).
- **GitLab** : `/label` quick actions inline (portable, pas de flag CLI
  spécifique).
- **JIRA** : wiki-markup, AC sous `*Acceptance criteria*` pour filtres natifs.

## Push initial des templates docs

Templates `docs-defaults/*.md` poussés via `docs-adapter.sh apply-template`
au premier setup, puis appliqués à chaque création de page.

## Templates additionnels (autres usages)

- `_shared/templates/daemon.sh.tpl` — script daemon `/develop --loop=daemon`.
- `_shared/templates/develop-daemon.sh.tpl` — variant daemon développe.
- `_shared/templates/session-start-hook.sh.tpl` — hook SessionStart opt-in
  (copie user-side).
