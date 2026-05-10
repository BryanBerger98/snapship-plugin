# Workflow détection & intégration

## Setup initial (premier `/define` — config absente)

`_shared/setup-config.sh` auto-discovery:

```
1. Parse .git/config → repository.{platform, http_url, ssh_url, default_branch}
2. Liste MCP servers actifs (parse claude_desktop_config / .claude/settings.json)
   → cherche: atlassian, github, gitlab, affine, notion, frame0
3. Pour chaque section requise par skill courant:
   - Si MCP trouvé pertinent → propose en option
   - Sinon → propose CLI dispo (which gh/glab/jira)
   - AskUserQuestion choix + paramètres
4. Setup detail par section:
   - tickets: platform + url + (si JIRA: jira.project_key + jira.workflow_states/transitions)
   - documentation:
     · Liste workspaces AFFiNE/Notion via MCP → AskUserQuestion choix
     · Liste pages templates (heuristique nom contient "Template") → mapping
     · Templates manquants → AskUserQuestion "Créer défauts maintenant ?"
       Oui: push depuis `templates/docs-defaults/{prd-feature,wireframes-gallery}.md` (v0.2 — `prd-global` retiré)
       Non: pages from scratch
     · Choix `root_page_id`: page existante ou créer "Produit"
   - wireframes: confirm frame0 ou skip
   - testing: auto-detect commandes + override
   - naming: defaults branch_pattern/commit_pattern + AskUserQuestion override
   - develop: review_cycles_max + severity_threshold + fail_strategy
   - qa: qa_cycles_max + severity_threshold + retrigger_review
   - defaults: lang (FR/EN)
5. AskUserQuestion confirm (montre aperçu)
6. Write `snapship.config.json` racine
```

Idempotent: si config existe partielle, propose update sections incomplètes uniquement.

## Runtime check (config présente) — `detect-platforms.sh`

**Source de vérité = `snapship.config.json`.** Aucune re-détection sauf vérif auth.

```
1. Read snapship.config.json (via load-config.sh)
2. Pour chaque platform configurée:
   - MCP server actif? (vérifier listing MCP)
   - Sinon CLI dispo? (which + auth check)
   - Si rien dispo → erreur claire avec instructions install/auth
3. Cache résultat session (in-memory, pas disque)
```

**Auth check par platform:**

- `gh auth status` (exit 0 = ok)
- `glab auth status`
- `jira me` (jira-cli ankitpokhrel)
- AFFiNE/Notion MCP: tente 1 read call, catch error

## Flux d'intégration docs/tickets par skill

```
/define (v0.2)
  ├─ step-04: render per-feature PRD localement (drop prd-global)
  ├─ step-05: push PRD page archive `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (immuable, taggé domains)
  │           + lookup-or-create domain + journey pages sous `{functional_root}/`
  └─ meta.json: { prd: {page_id, url, path}, domains[], impacted_journeys[] }
     domains.json: { <domain>: {domain_page_id, journeys: { <slug>: {page_id, url} }} }

/snap:doc-import (v0.2 — bootstrap legacy)
  └─ AI cluster pages doc legacy → restructure (synthesize|copy|move)
     → populate domains.json one-shot

/snap:doc-update (v0.2 — auto post-QA si auto_update_on_qa_success)
  ├─ step-01: fetch PRD + journey pages courantes + git diff feature
  ├─ step-02: AI patch (mode=diff) ou rewrite (mode=rewrite)
  └─ step-03: push update-page-content (PRD jamais touché)

/ticket
  ├─ step-00: lit PRD feature depuis docs platform (MCP fetch via meta.json.prd.page_id)
  ├─ step-05 (push): lien PRD ajouté en description ticket
  └─ Optionnel: ajoute liens tickets dans page docs feature (section "Tickets")

/wireframe
  ├─ step-00: lit tickets cache + page docs feature
  ├─ step-03: crée page "Wireframes Gallery" sub-page de PRD feature
  │           - upload PNG via blob MCP
  │           - embed images + liens tickets + liens Frame0
  └─ Update tickets plateforme avec lien gallery

/develop
  ├─ step-02: lit ticket + lit PRD feature docs → contexte enrichi + crée branche
  │           (apply-naming.sh branch idempotent, skip si branch_mode=false)
  ├─ step-03a: 2 phases
  │  ├─ Phase 1 — Code: workflow inline analyze/plan/execute/validate
  │  └─ Phase 2 — Review cycle (max `review_cycles_max`):
  │              · 3 reviewers parallèles (technical, functional, security)
  │              · severity check per type vs `reviews.{type}.severity_threshold`
  │              · 1 dev agent applique {aggregated_feedback}
  │              · early stop si TOUS types < seuil (premier batch clean accepté)
  │  → 1 commit atomique par ticket (amend si fixes Phase 2)
  └─ step-04: push commits + sync ticket + crée PR/MR
              (template `repository.pr_template_path` ou fallback `_shared/templates/pr-default.md`)

/qa  (skill séparée — validation runtime)
  ├─ step-00: charge meta.json + tickets.json + détermine diff scope (commits ticket/feature)
  ├─ step-01-collect: raw outputs (régression scope=impacted via code-review-graph + wireframe via Playwright)
  ├─ step-02-interpret: spawn `code-reviewer-qa` subagent → severity + feedback_md
  ├─ step-03-fix: cycle dev↔qa (max `qa.qa_cycles_max`)
  │             · exit si regression=pass ET wireframe=pass ET severity < threshold
  │             · fixes amend commit ticket atomique
  └─ step-04-retrigger (opt-in `qa.retrigger_review=true` ET fixes appliqués):
              · re-run 3 reviewers /develop sur diff post-QA (1 retrigger max)
```

## Error handling (MCP/CLI fail mid-workflow)

**Politique: fail-fast + resume.**

```
Tout appel MCP/CLI échoué (timeout, auth, API error):
  1. Skill catch erreur, capture stack trace + step name
  2. Update progress.md avec:
     - timestamp, step échoué, erreur exacte
     - état partiel (variables clés, IDs créés avant fail)
  3. Affiche message clair:
     - Cause probable (auth expirée, MCP server down, rate limit)
     - Action requise user (re-auth, restart MCP, attendre)
     - Commande resume: `/<skill> -r {feature_id}`
  4. Exit non-zéro → workflow stop net
```

**Idempotence:** chaque step doit être ré-exécutable sans dupliquer:

- `/snap:define`: avant create page PRD, check `meta.json.prd.page_id` existe (v0.2)
- `/ticket`: avant create ticket, check si déjà push (cache `tickets.json`)
- `/wireframe`: blob upload checksum-based dedup
- `/develop`: branch checkout idempotent, commit message diff-based

**Pas de retry auto.** User décide après diagnostic.
