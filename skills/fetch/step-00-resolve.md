---
step: 00-resolve
next_step: 01-fetch
description: Parse args, enumère features + kinds à fetch, lit chaque manifest pour récupérer la liste des refs distantes à pull.
---

# step-00 — resolve fetch targets

## Tâches

1. **Parse args** `/snap:fetch` :
   - `--feature=SLUG`, `--kind=K|all`, `--all`, `--check`, `--probe-tracker`,
     `--dry-run`.
   - Validation : `--feature` ET `--all` mutuellement exclusifs.
   - `--probe-tracker` mutuellement exclusif avec `--feature`/`--all`/`--kind` :
     ```bash
     if [ "$PROBE_TRACKER" = "true" ] && { [ -n "$FEATURE" ] || [ "$ALL" = "true" ] || [ -n "$KIND" ]; }; then
       echo "ERROR: --probe-tracker is exclusive with --feature/--all/--kind" >&2
       exit 1
     fi
     ```
   - `--kind=tickets` rejeté en v1.2 :
     ```bash
     if [ "$KIND" = "tickets" ]; then
       echo "ERROR: --kind=tickets removed in v1.2 (tracker = single source)." >&2
       echo "       Use /snap:fetch --probe-tracker for tracker health check." >&2
       exit 1
     fi
     ```
   - Sans `--feature` ni `--all` ni `--probe-tracker` → ERROR avec aide.

2. **Probe-tracker short-circuit** (saute step-00 features enumeration, jumps
   direct to step-01) :
   ```bash
   if [ "$PROBE_TRACKER" = "true" ]; then
     jq -n '{mode:"probe-tracker", dry_run:'"${DRY_RUN:-false}"',targets:[]}' \
       > .snap/.fetch-plan.json
     # step-01 lit le mode et exécute probe au lieu de fetch
     continue_to step-01
   fi
   ```

3. **Lit config** (`bash skills/_shared/load-config.sh`) :
   - `documentation.platform` (notion/affine/none)
   - `design.platform` (penpot/figma)
   - `tickets.platform` (seulement lu si `--probe-tracker`).

4. **Énumère features** :
   ```bash
   if [ -n "$FEATURE" ]; then
     FEATURES=("$FEATURE")
   else
     FEATURES=($(ls .snap/manifests/*.manifest.json | xargs -n1 basename | sed 's/\.manifest\.json$//'))
   fi
   ```

5. **Énumère kinds par feature** :
   - `--kind=prd` → `[prd]`
   - `--kind=design` → `[design_gallery, design_file]`
   - `--kind=wireframe` → `[wireframes_gallery]`
   - `--kind=all` (défaut feature) → tout ce qui existe dans `manifest.refs.*`
   - **`tickets` n'est plus un kind valide** (drop v1.2).

6. **Build plan JSON** :
   ```json
   {
     "mode": "fetch" | "check" | "probe-tracker",
     "dry_run": false,
     "targets": [
       { "story_id": "01-auth", "kind": "prd",
         "ref": { "platform":"notion", "page_id":"abc", "synced_at":"..." } },
       ...
     ],
     "taxonomy_refresh": true
   }
   ```
   Persiste dans `.snap/.fetch-plan.json` (ephémère).

7. **Mode `--check`** : sortie immédiate post-step-00 avec compare logic
   (court-circuite step-01/02/03) :
   ```bash
   for target in $TARGETS; do
     # pull last_edited_time uniquement (cheap MCP call)
     # compare to ref.synced_at
     # if remote > local → sync-fetch.sh check-mark
   done
   ```

8. **Telemetry + progress** :
   ```bash
   bash skills/_shared/progress.sh start --skill=fetch --story-id=_global
   bash skills/_shared/progress.sh step --skill=fetch --story-id=_global \
     --step-num=00 --step-name=resolve --status=ok
   ```

## Continue à

`step-01-fetch.md` (sauf `--check` → step-05 finish-like direct).
