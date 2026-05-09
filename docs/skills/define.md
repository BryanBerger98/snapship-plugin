# Skill `/define`

Définit produit et features. Brainstorm PRD interactif, détecte projet existant, génère PRD global + mini-PRDs feature.

## Frontmatter

```yaml
name: define
description: Définit produit et features. Brainstorm PRD interactif, détecte projet existant, génère PRD global + mini-PRDs feature.
argument-hint: "[-a] [-i] [-r <feature-id>] [--existing] [--dry-run] [<feature description>]"
```

## Flags

- `-a` autonomous (skip confirms)
- `-i` interactive flag config
- `-r <id>` resume
- `--existing` force discovery mode
- `--lang en` override langue
- `--dry-run` preview sans write calls

## State variables

- `{project_path}`, `{product_dir}` = `.claude/product/` (path hardcoded, non-configurable)
- `{has_existing_prd}` (bool)
- `{has_codebase}` (bool, détecté)
- `{feature_name}`, `{feature_id}` (NN-kebab)
- `{auto_mode}`, `{lang}`

## Steps

### step-00-init

Parse flags, vérifie `.claude/product/`. Détecte `{has_codebase}` (présence `.git/` ou fichiers source). Si index.md existe + features → propose update vs new feature. Resume `-r 02` → cherche `features/02-*`.

### step-01-discover

Skip si `{has_codebase}=false` — green-field brainstorm direct.

- Lance 2-4 agents parallèles `explore-codebase`:
  - Architecture globale + stack technique
  - Features existantes + parcours utilisateur
  - État des tests + qualité code
  - TODO/FIXME/dette technique (optionnel)
- Synthèse: AS-IS du produit
- **Cas green-field** (`has_codebase=false`): aucune AS-IS, jump direct step-02. Tagué `{green_field}=true` → step-02 enrichit context externe.

### step-02-vision

- AskUserQuestion progressive: vision 1-phrase → problème → success → users
- Si projet existant: contextualise avec AS-IS
- **Si `{green_field}=true`**: spawn 2 agents `general-purpose` parallèles AVANT AskUserQuestion:
  1. Recherche concurrents espace produit (web search depuis pitch user 1-phrase)
  2. Références UX patterns / produits inspiration similaires
  - Synthèse 5-10 bullets (concurrents clés, gaps observés, patterns réutilisables) injectée comme context préliminaire dans prompt vision
  - User valide/dévie → AskUserQuestion progressive ensuite
- A/P/C menu fin de phase

### step-03-features

- AskUserQuestion: liste features clés + priorisation (must/should/could/won't)
- Reflète back en tableau
- User choisit première feature à mini-PRD

### step-04-write-prd (AFFiNE)

- Vérifie `artysan.config.json` section `documentation`. Si absente/incomplète → run `_shared/setup-config.sh` (auto-discovery workspace/templates, AskUserQuestion mapping)
- Génère contenu PRD global: vision + problème + users + features prioritaires + scope/out-of-scope
- Crée page AFFiNE via MCP:
  - Si `templates.prd_global` set → duplique template, remplit variables (titre, sections)
  - Sinon → crée page from scratch en markdown, push via MCP
  - Page sous `root_page_id` du workspace
- Génère mini-PRD feature: vision feature, scope, key capabilities, phases, out-of-scope, ref code
- Crée sub-page AFFiNE feature sous PRD global (même logique template)
- Sauvegarde IDs dans `meta.json` feature: `{ "affine_page_id": "...", "affine_url": "..." }`
- Update `.claude/product/index.md` (état: `defined` + lien AFFiNE)
- AskUserQuestion validation finale (montre URL AFFiNE pour review)

### step-05-finish

- Affiche path PRD, summary
- Propose: `Lancer /ticket {feature-id} ?` via AskUserQuestion
