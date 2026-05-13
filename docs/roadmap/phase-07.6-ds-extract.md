# Phase 7.6 — `/design ds-extract` mode (LLM-driven React → YAML CSpec)

**Objectif:** ajouter mode `ds-extract` à `/design` — Claude lit composants React existants et émet `design-system/specs/{atomic,molecular,organism}.yaml` (CSpec Bridge-compatible). Bootstrap one-shot code → YAML → Figma (`ds-init`). **Figma devient source de vérité après extract — pas de sync inverse.**

**Non-breaking** : nouveau mode opt-in, n'affecte pas `ds-init` / `ds-update` / `mockup` existants. Bump 0.5 → 0.6.0 (mineur, additive).

## 7.6.1 Décisions verrouillées

| #                  | Décision                                                                                                                |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Scope              | One-shot React → YAML CSpec. Pas de reverse Figma → YAML (Figma master après init).                                     |
| Implémentation     | **LLM-driven.** Claude lit `design.extract.source` et émet directement les YAML. Pas de parser dédié, pas de Node CLI, pas de build. |
| Stack supportée    | **Agnostic.** Tailwind+cva, styled-components, CSS Modules, MUI, vanilla CSS, patterns custom (HOC, render props).      |
| Tokens             | Si Tailwind détecté → Claude lit `tailwind.config.{ts,mjs,cjs,js}` pour mapper classes → tokens (`bg-brand-500` → `{colors.brand.500}`). |
| Classification     | Atomic = 0 import composant projet. Molecular = imports atomic uniquement. Organism = imports molecular OU ≥ 2 atomic. Override via comment `// @ds-category: <atomic\|molecular\|organism>`. |
| Position pipeline  | Mode `ds-extract` exécuté avant `ds-init`. Chaînage manuel par défaut (revue YAML entre les deux). Flag `--chain-init` pour pipe direct. |
| Sync après init    | Désactivée — `ds-update` documentée comme "patch YAML → Figma" (skill spec-driven), pas "code → Figma". User édite directement dans Figma post-init. |
| Trade-off assumé   | Non-déterministe (deux runs peuvent diverger). Acceptable car one-shot + relu par user avant push Figma.                |

## 7.6.2 Implémentation

### Step skill (`skills/design/step-01b-ds-extract.md`)

Instructions LLM-driven :
1. Resolve config `design.extract.{source,out,category_override_marker}`.
2. Validate `source` existe + ≥ 1 fichier React détecté.
3. Pre-flight Figma confirmation (rappel : Figma master après init).
4. Lister composants (`.tsx`/`.jsx`/`.ts`/`.js`, exclure tests/stories).
5. Si Tailwind détecté → lire `tailwind.config.{ts,mjs,cjs,js}` pour mapping tokens.
6. Classifier atomic/molecular/organism via graphe imports (fixed-point + override commentaire).
7. Émettre `$out/{atomic,molecular,organism}.yaml` (CSpec Bridge-compatible).
8. Persister `.design-cache.json` flag `extract.ran_at`.
9. Chaîner `step-01-ds-bootstrap.md` si `--chain-init`.

### Config opt-in (`design.extract`)

```json
{
  "design": {
    "platform": "figma",
    "extract": {
      "source": "src/components",
      "out": "design-system/specs",
      "category_override_marker": "@ds-category"
    }
  }
}
```

Défauts résolus par `load-config.sh` uniquement si bloc présent (skill désactivé sinon).

### Schema + wizard

- `skills/_shared/schemas/config.schema.json` : bloc `design.extract` avec `additionalProperties: false`.
- `skills/_shared/setup-config.sh` : flags `--design-extract-opt-in=true|false`, `--design-extract-source=PATH`, `--design-extract-out=PATH`.

### Skill SKILL.md + step-00

- `ds-extract` ajouté à la table des modes.
- `step-00-init.md` parse args supporte `--mode=ds-extract` + `--chain-init`.
- Mode resolver short-circuit pour `ds-extract` (skip auto-detect — jamais auto-résolu).

## 7.6.3 Historique — pivot LLM-driven

**Prototype initial** (abandonné) : Node CLI sous `tools/ds-extract/` avec ts-morph + `tailwindcss/resolveConfig` + classification fixed-point + 25 tests vitest + helper shell wrapper.

**Pivot** : sur-ingéniéré pour un mode one-shot. Coûts (build step, `node_modules`, npm deps, contraintes stack Tailwind+cva uniquement) > bénéfices (déterminisme, performance — pas critique en one-shot). Pattern LLM-driven plus cohérent avec philosophie plugin (helpers shell = actions déterministes ; logique métier = Claude).

**Décision documentée** : `docs/decisions.md` section "v0.6 — ds-extract one-shot React → YAML".

## 7.6.4 Acceptance check

- `design.extract.source` existe + contient ≥ 1 composant React.
- `design-system/specs/{atomic,molecular,organism}.yaml` écrits (write mode) ou preview JSON affiché (dry-run).
- `.design-cache.json` mis à jour avec `extract.ran_at`.
- Si `--chain-init` → pipeline continue dans step-01 (push Figma).
- Mode jamais auto-résolu par step-00 (explicit only).

## 7.6.5 Hors-scope (Phase 7.7+)

- Reverse sync Figma → code (utiliser Figma Dev Mode + Code Connect).
- Validation déterministe du YAML émis (tests AST-based, pas LLM-output).
- Watch mode (re-extract on save).
- Diff visuel YAML précédent vs nouveau.

## 7.6.6 Effort estimé

~1.5j (LLM-driven simplifie drastiquement vs ~5.5j parser AST initial).
