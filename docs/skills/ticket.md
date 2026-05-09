# Skill `/ticket`

Génère tickets complets adaptés à JIRA/GitLab/GitHub depuis mini-PRD feature. Draft local → review batch → push.

## Frontmatter

```yaml
name: ticket
description: Génère tickets complets adaptés à JIRA/GitLab/GitHub depuis mini-PRD feature. Draft local → review batch → push.
argument-hint: "[-a] [-r] [--platform=auto|jira|gh|glab] [--dry-run] <feature-id>"
```

## Flags

- `-a` autonomous (skip AskUserQuestion, fallback recommended)
- `-r {task-id}` resume tâche en cours (partial match)
- `-i` interactif strict (force AskUserQuestion partout)
- `--platform` override détection
- `--dry-run` génère local sans push

## Steps

### step-00-init

Load PRD feature depuis AFFiNE (lit `meta.json` → `affine_page_id` → MCP fetch). Lance `_shared/detect-platforms.sh --section=tickets`:

1. Lit `config.tickets.platform` (résolu via `load-config.sh`)
2. Vérifie MCP/CLI dispo + auth pour cette platform
3. Si rien dispo → erreur claire (install/auth instructions)
- Cache in-memory session uniquement (config = source de vérité)

### step-01-decompose

- Lit PRD feature (contenu AFFiNE déjà chargé)
- Décompose en stories atomiques (5-30min, 1-5 fichiers, indépendantes)
- Ordre par priority + dépendances

### step-02-enrich (parallel agents)

- `explore-codebase` → patterns code à suivre par story
- `explore-docs` si lib unfamiliar
- `websearch` pour gotchas
- Enrichit chaque story: contexte, tech notes, edge cases, refs fichiers

### step-03-format

Adapte selon `{platform}`:

- **JIRA**: titre, description (Atlassian markdown), AC (checklist), labels, story points hint, parent epic
- **GitHub Issues**: titre, body markdown, labels, assignees, milestone, task lists
- **GitLab**: idem GitHub + scoped labels, weight
- Templates dans `templates/ticket-{platform}.md`

### step-04-review

- Affiche tableau récap (id, titre, priorité, taille estimée)
- AskUserQuestion: approve all / adjust / re-decompose
- Si adjust: AskUserQuestion par ticket sélectionné

### step-05-push

Si pas `--dry-run`:

- Sauvegarde local `tickets.json` (cache avec id plateforme après push)
- Loop sur stories approuvées:
  - Via MCP (priorité) ou CLI shell
  - Récupère ID plateforme, sauvegarde dans cache
- Update `index.md` état: `ticketed`

### step-06-finish

Propose `/wireframe {feature-id}` (si feature UI) ou `/develop {feature-id}`.
