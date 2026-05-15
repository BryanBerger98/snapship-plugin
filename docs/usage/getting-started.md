# Getting started — première feature en 5 minutes

Pré-requis : plugin installé ([install.md](install.md)) et `claude` lancé
depuis la racine d'un repo Git.

## 1. `/snap:init` — bootstrap workspace

Lancer **une fois par projet** :

```text
/snap:init
```

Snap probe l'environnement (`.git/config`, MCPs actifs, `package.json`,
`pyproject.toml`…) et propose les defaults via `AskUserQuestion`. Réponse
type :

| Question     | Réponse exemple                              |
| ------------ | -------------------------------------------- |
| Repo         | `github` (détecté depuis `.git/config`)      |
| Tickets      | `linear`                                     |
| Docs         | `notion`                                     |
| Wireframes   | `frame0`                                     |
| Design       | `figma` (optionnel)                          |
| Lang         | `fr`                                         |

Mode autonome — utilise tous les defaults détectés :

```text
/snap:init --auto
```

À la sortie :

```
<project>/
  snapship.config.json     # ← committable, partagé équipe
  .snap/                   # ← workspace local
    manifests/             # ← committed (références plateformes)
    tickets/               # ← committed (cache tickets)
    PRDs/ designs/ wireframes/ queues/   # ← gitignored (staging)
    progress.json          # ← gitignored (état runtime)
```

> Re-init plus tard : `/snap:init --force` (réécrit `snapship.config.json`,
> **préserve** `.snap/`).

## 2. `/snap:define` — première feature

```text
/snap:define "Authentification email + magic link"
```

Pipeline :

1. **step-00** crée le `feature_id` (ex. `01-auth-email`) et le slug.
2. **step-01..03** brainstorm interactif PRD : objectif, scope, écrans,
   critères d'acceptation. Réponses via `AskUserQuestion`.
3. **step-04** écrit `.snap/PRDs/01-auth-email.md` + push vers la plateforme
   docs configurée (Notion/AFFiNE). La page distante devient source de
   vérité ; le local sert au staging.
4. **step-05** crée `.snap/manifests/01-auth-email.manifest.json` avec
   `state: defined` et `refs.prd_page = { platform, page_id, url, synced_at }`.

Reprise possible à tout instant : `/snap:define --resume` (ou `-r`).

## 3. `/snap:ticket` — décomposer en tickets

```text
/snap:ticket 01-auth-email
```

Lit le PRD, propose une décomposition en tickets typés conventional commit
(`feat`, `fix`, `chore`…), te demande confirmation, écrit
`.snap/tickets/01-auth-email.json`, puis pousse sur la plateforme tickets
configurée (GitHub Issues, GitLab, JIRA, Linear). Chaque ticket gagne un
`platform_id` (`#42`, `PROJ-123`…) et une `url`.

Templates repo-native : si ton repo expose `.github/ISSUE_TEMPLATE/*.md` ou
`.gitlab/issue_templates/*.md`, snap les détecte et les remplit
section-par-section au lieu d'écrire le bundled template. Voir
[templates.md](../contributing/templates.md).

## 4. (optionnel) `/snap:wireframe` puis `/snap:design`

Si la feature a au moins un ticket UI :

```text
/snap:wireframe                 # low-fi via Frame0/Penpot/Figma
/snap:design 01-auth-email      # hi-fi via Penpot/Figma
```

Chaque skill génère les assets, push vers la plateforme, back-linke
`wireframe_url` + `design_url` dans `tickets/{feature_id}.json`.

## 5. `/snap:develop` — implémenter ticket par ticket

```text
/snap:develop 01-auth-email          # batch tous les tickets de la feature
# ou
/snap:develop t-001                  # un ticket précis (local_id ou platform_id)
```

Loop **standalone** ou **session** :

- standalone : un ticket → un commit atomique → continue.
- session : enchaîne tous les tickets ouverts d'une feature jusqu'au PR.

Trois reviewers automatiques (technical / functional / security) tournent
post-commit ; un PR brouillon est ouvert avec le résumé.

> Le mode `daemon` a été retiré en v1.0.0. Pas de boucle hors-session.

## 6. `/snap:qa` — validation runtime

```text
/snap:qa 01-auth-email
```

Lance les tests scope régression (via `code-review-graph` impact radius si
disponible), puis un diff visuel Playwright vs les wireframes/maquettes
référencés dans les tickets. Échec critique → ré-ouvre les tickets concernés
en `qa_blocked`.

## Cycle complet

```text
/snap:init                           # 1× par projet
/snap:define "..."                   # 1× par feature
/snap:ticket   <feature_id>
/snap:wireframe                      # si UI
/snap:design   <feature_id>          # si UI hi-fi
/snap:develop  <feature_id>
/snap:qa       <feature_id>
/snap:doc-update <feature_id>        # post-ship — rafraîchit la doc fonctionnelle
```

Voir [workflow.md](workflow.md) pour les détails plateformes et
[skills/](skills/) pour chaque skill (flags, pipeline, outputs).

## Si ça casse

[troubleshooting.md](troubleshooting.md) — auth MCP, conflits resume,
secrets, sync fail, version mismatch.
