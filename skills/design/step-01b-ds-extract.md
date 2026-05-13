---
step: 01b-ds-extract
next_step: 01-ds-bootstrap | end
description: Read React component library → emit YAML CSpec (atomic/molecular/organism). LLM-driven, stack-agnostic (Tailwind+cva, styled-components, CSS Modules, etc.). Optional chain into ds-init.
---

# step-01b — ds-extract (React → YAML CSpec)

Executed **only when** `--mode=ds-extract` is explicitly passed. This mode is
*not* auto-resolved by step-00 — it must be explicitly requested to avoid
regenerating YAML after Figma has become the source of truth.

> **Important.** After running `ds-extract` and `ds-init` once, **Figma is
> the source of truth**. Do not re-run `ds-extract` to "sync" code back into
> the YAML — it will overwrite design decisions made in Figma. To propagate
> Figma changes back to code, use Figma Dev Mode + Code Connect (out of this
> skill's scope).

## Approach

Pas de parser dédié. Claude lit directement les composants sources et émet
les YAML CSpec. Avantages :

- **Stack-agnostic.** Tailwind + cva, styled-components, CSS Modules, vanilla
  CSS, MUI, Chakra — tous supportés tant que le code est lisible.
- **Zero tooling.** Aucun build, aucun `node_modules`, aucune dépendance npm
  externe (au-delà de ce que la skill utilise déjà).
- **Adapt aux patterns custom** — HOC, render props, variants ad-hoc.

Contrepartie acceptée : non-déterministe, output relu par user avant push
Figma. One-shot bootstrap, pas re-exécuté après init.

## Tasks

1. **Resolve extract config** depuis `config.design.extract` :
   ```bash
   extract_source=$(jq -r '.design.extract.source // "src/components"' /tmp/cfg.json)
   extract_out=$(jq -r '.design.extract.out // "design-system/specs"' /tmp/cfg.json)
   extract_marker=$(jq -r '.design.extract.category_override_marker // "@ds-category"' /tmp/cfg.json)
   ```

2. **Validate input** :
   - `$extract_source` directory exists.
   - At least one `.tsx` / `.jsx` / `.ts` / `.js` file under `$extract_source`
     (`find "$extract_source" -type f \( -name '*.tsx' -o -name '*.jsx' -o -name '*.ts' -o -name '*.js' \) | head -1`).
   - If empty :
     ```text
     ERROR: no React component files found under $extract_source.
     Set design.extract.source in snapship.config.json.
     ```

3. **Pre-flight Figma confirmation** — afficher message :
   ```text
   ds-extract va lire les composants React sous $extract_source et émettre
   $extract_out/{atomic,molecular,organism}.yaml.

   Rappel : après push Figma (--chain-init ou /design --mode=ds-init manuel),
   Figma devient source de vérité. Ne pas re-run ds-extract ensuite.
   ```

4. **Lire le code** :
   - Lister tous les composants sous `$extract_source` (récursif, exclure
     `*.test.*`, `*.spec.*`, `*.stories.*`, `__tests__/`).
   - Lire **tous** les fichiers composants (chaque export React de premier
     niveau = candidat composant).
   - Si projet utilise Tailwind, lire aussi `tailwind.config.{ts,mjs,cjs,js}`
     (chercher à la racine et un niveau au-dessus de `$extract_source`) pour
     résoudre les classes utilitaires → tokens (`bg-brand-500` →
     `{colors.brand.500}`, `text-sm` → `{fontSize.sm}`, etc.). Si pas de
     config détectée, émettre les classes raw dans `raw_classes` et un
     warning.

5. **Classifier atomic / molecular / organism** :
   - **atomic** — aucun import d'un autre composant local (purement
     primitif, ex: `Button`, `Input`, `Label`).
   - **molecular** — importe 1 atomic (ex: `Card` qui contient un
     `Button`).
   - **organism** — importe ≥ 2 atomics, ou ≥ 1 molecular, ou patterns de
     layout complexes (header, sidebar, form complet).
   - **Override commentaire** : si le fichier contient
     `// $extract_marker: atomic|molecular|organism` (ex:
     `// @ds-category: organism`), respecter l'override.
   - Algorithme : fixed-point sur graphe d'imports. Itérer jusqu'à
     stabilisation.

6. **Émettre les YAML CSpec** sous `$extract_out/` :
   - `atomic.yaml`, `molecular.yaml`, `organism.yaml`.
   - Format CSpec (Bridge-compatible) :
     ```yaml
     version: "1"
     category: atomic
     components:
       - name: Button
         source: src/components/Button.tsx
         base:
           padding: "{spacing.4}"
           borderRadius: "{borderRadius.md}"
         variants:
           intent:
             primary:
               backgroundColor: "{colors.brand.500}"
               color: "{colors.white}"
             ghost:
               backgroundColor: transparent
               color: "{colors.brand.500}"
           size:
             sm: { fontSize: "{fontSize.sm}" }
             md: { fontSize: "{fontSize.base}" }
         defaults:
           intent: primary
           size: md
         props:
           - { name: disabled, type: boolean, required: false }
         warnings: []
     ```
   - Si Tailwind détecté + classe arbitrary (`bg-[#abc123]`) ou classe non
     résoluble → ajouter `warnings: [...]` au composant + lister dans le
     summary.

7. **Persister `.design-cache.json`** :
   ```json
   {
     "extract": {
       "ran_at": "<ISO timestamp>",
       "source": "<extract_source>",
       "out": "<extract_out>",
       "atomic_count": N,
       "molecular_count": N,
       "organism_count": N,
       "warnings": [ ... ]
     }
   }
   ```
   Flag qui signale aux futurs runs que Figma peut être devenu source of
   truth.

8. **Surface summary** (human-readable) :
   ```text
   ds-extract: atomic=N, molecular=N, organism=N, warnings=N
   YAML écrit sous $extract_out/.
   ```
   Si `warnings > 0` → lister chacune.

9. **Update progress** :
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id=_global \
     --step-num=01b \
     --step-name=ds-extract \
     --status=ok \
     --skill=design \
     --extra="{\"atomic\":$atomic,\"molecular\":$molecular,\"organism\":$organism}"
   ```

## Dry-run

Si `--dry-run` passé :
- Lire les composants (même flow).
- Construire le YAML en mémoire.
- **Ne pas écrire** `$extract_out/*.yaml` ni `.design-cache.json`.
- Afficher preview JSON résumé (atomic/molecular/organism counts +
  composant names + warnings).

## Chain into ds-init

Si `--chain-init` passé, **continuer vers `step-01-ds-bootstrap.md`** avec
`mode=ds-init`. Sinon halt avec message succès :
`"YAML écrit sous $extract_out. Review, puis run /design --mode=ds-init."`.

## Acceptance check

- `$extract_source` lu, ≥ 1 composant détecté.
- `$extract_out/{atomic,molecular,organism}.yaml` écrits (write mode) ou
  preview affiché (dry-run).
- `.design-cache.json` mis à jour avec `extract.ran_at`.

## Next step

- `--chain-init` set → `step-01-ds-bootstrap.md`
- Otherwise → halt with success message.
