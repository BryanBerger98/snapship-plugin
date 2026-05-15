# `/snap:init` — bootstrap du workspace

Initialise SnapShip dans le projet courant : détecte les plateformes, demande
confirmation, écrit `snapship.config.json` et crée l'arborescence
`.snap/`.

## À quoi ça sert

`/snap:init` est le **point d'entrée obligatoire**. Tous les autres skills
(`/snap:define`, `/snap:ticket`, `/snap:wireframe`, `/snap:design`,
`/snap:develop`, `/snap:qa`, …) refusent de s'exécuter si
`snapship.config.json` est absent et renvoient ici.

## Quand l'utiliser

- **Nouveau projet** : rien de SnapShip n'existe encore.
- **Adoption sur projet existant** : détecte `.git/config`, les serveurs MCP
  actifs et la structure du projet pour pré-remplir les valeurs par défaut.
- **Ré-init** : `--force` réécrit un `snapship.config.json` existant sans
  toucher au contenu de `.snap/`.

À lancer **une seule fois par projet**.

## Syntaxe

```
/snap:init [--auto|-a] [--lang=fr|en] [--force]
```

## Flags

| Flag             | Effet                                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------- |
| `--auto` / `-a`  | Mode autonome : ignore les questions, utilise chaque valeur détectée. Échoue si un champ requis reste non résolu (ex. aucun MCP docs détecté). |
| `--lang=fr\|en`  | Force `defaults.lang` dans la config (défaut : `fr`).                                                   |
| `--force`        | Réécrit un `snapship.config.json` existant. Sans danger : ne touche pas à `.snap/`.            |

## Pipeline

| #  | Step                | Rôle                                                                          |
| -- | ------------------- | ----------------------------------------------------------------------------- |
| 00 | `step-00-detect.md` | Sonde l'environnement, propose les réponses via `AskUserQuestion` (ou auto).   |
| 01 | `step-01-write.md`  | Écrit `snapship.config.json`, crée `.snap/`, valide contre le schéma.|

Les steps sont **idempotents** : relancer `step-01-write` avec `--force` sur
des entrées identiques produit une config identique.

## Outputs

- `<projet>/snapship.config.json` — validé contre `config.schema.json`.
- `<projet>/.snap/` :
  ```
  .snap/
    features/
    progress.json            # journal de run (header seul à l'init)
    telemetry.ndjson       # prêt pour append via skills/_shared/telemetry.sh
    .config-resolved.json  # produit par load-config.sh
  ```
- Entrée de télémétrie `init step-01 write — ok`.

## Étape suivante

`/snap:define` pour rédiger le PRD de la première feature.
