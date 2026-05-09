# Diagrammes workflow

Schémas visuels Mermaid. Vue globale + zooms par skill + variantes.

## 1. Vue globale (chaîne 5 skills)

```mermaid
flowchart LR
    U([User]) -->|idée produit| DEFINE
    DEFINE[/define/] -->|PRD global + feature<br/>AFFiNE| TICKET
    TICKET[/ticket/] -->|tickets push<br/>JIRA/GH/GL| WF{UI feature?}
    WF -->|oui| WIREFRAME[/wireframe/]
    WF -->|non| DEVELOP
    WIREFRAME -->|wireframes Frame0<br/>+ gallery AFFiNE| DEVELOP[/develop/]
    DEVELOP -->|commits atomiques<br/>+ PR/MR| QA[/qa/]
    QA -->|validated| END([Ship])

    classDef skill fill:#2d3748,stroke:#4a5568,color:#fff
    class DEFINE,TICKET,WIREFRAME,DEVELOP,QA skill
```

## 2. Storage & sources de vérité

```mermaid
flowchart TB
    subgraph LOCAL[".claude/product/ (cache local)"]
        IDX[index.md]
        FEAT[features/NN-slug/]
        FEAT --> META[meta.json]
        FEAT --> TIX[tickets.json]
        FEAT --> PROG[progress.md]
        FEAT --> WIRES[wireframes/]
    end

    subgraph EXT["Sources de vérité (externes)"]
        AFFINE[(AFFiNE<br/>PRD global<br/>PRD feature<br/>Gallery)]
        PLAT[(Plateforme tickets<br/>JIRA/GH/GL)]
        FRAME[(Frame0<br/>shapes + PNG)]
        GIT[(Git repo<br/>branches + commits)]
    end

    META -.affine_page_id.-> AFFINE
    TIX -.IDs plateforme.-> PLAT
    WIRES -.frame0_page_id.-> FRAME
    META -.branch_name.-> GIT
```

## 3. `/define` — flux interactif

```mermaid
flowchart TB
    S0[step-00-init] --> DETECT{has_codebase?}
    DETECT -->|oui| S1[step-01-discover<br/>2-4 agents parallèles<br/>explore-codebase]
    DETECT -->|non| GREEN[green_field=true<br/>spawn 2 agents:<br/>concurrents + UX refs]
    S1 --> S2[step-02-vision<br/>AskUserQuestion progressive]
    GREEN --> S2
    S2 --> S3[step-03-features<br/>liste + priorisation MoSCoW]
    S3 --> S4[step-04-write-prd<br/>AFFiNE: PRD global + feature]
    S4 --> S5[step-05-finish<br/>propose /ticket]
```

## 4. `/develop` standalone — 2 phases + cycle review

```mermaid
flowchart TB
    INIT[step-00-init<br/>+ step-01-fetch<br/>+ step-02-prepare<br/>branche idempotente]

    INIT --> P1[Phase 1: Code]
    subgraph P1[Phase 1: Code]
        A[analyze<br/>impact_radius]
        P[plan<br/>A/P/C menu]
        E[execute<br/>Edit/Write]
        V[validate<br/>typecheck/lint/test]
        A --> P --> E --> V
        V -.fail max 3.-> E
    end

    P1 --> P2[Phase 2: Reviews parallèles]
    subgraph P2[Phase 2: Reviews parallèles]
        BATCH[1 message<br/>3 Agent calls parallèles]
        BATCH --> RT[reviewer-technical]
        BATCH --> RF[reviewer-functional]
        BATCH --> RS[reviewer-security]
        RT --> AGG{tous severity<br/>< threshold?}
        RF --> AGG
        RS --> AGG
        AGG -->|non| FIX[dev agent applique<br/>aggregated_feedback]
        FIX --> BATCH
        AGG -->|oui| OK([Phase 2 OK])
    end

    P2 --> COMMIT[Commit atomique<br/>1 ticket = 1 commit<br/>amend si fixes]
    COMMIT --> SYNC[step-04-sync<br/>push + PR + update ticket]
    SYNC --> FIN[step-05-finish<br/>propose /qa]

    AGG -.max cycles atteint.-> STRAT{fail_strategy}
    STRAT -->|next-ticket| FIN
    STRAT -->|stop| STOP([Stop])
    STRAT -->|retry max 1| P1
```

## 5. `/develop` modes loop (3 variantes)

```mermaid
flowchart LR
    ARG[<arg>] --> MATCH{format?}
    MATCH -->|ticket-id| STD[Standalone<br/>1 ticket = 1 cycle]
    MATCH -->|NN-kebab| LOOP{--loop=?}
    LOOP -->|none| ASK[AskUserQuestion<br/>session ou daemon?]
    LOOP -->|session| SESS[Loop séquentiel<br/>même session<br/>step-03b]
    LOOP -->|daemon| DAEMON[Génère daemon.sh<br/>step-03c<br/>user lance manuellement]

    SESS --> ITER[Pour chaque ticket:<br/>step-03a Phase 1+2<br/>+ commit atomique]
    ITER --> NEXT{tickets<br/>restants?}
    NEXT -->|oui| ITER
    NEXT -->|non| PUSH[Push branch en bloc<br/>step-04-sync]

    DAEMON --> MANUAL[bash daemon.sh -n 20<br/>boucle externe<br/>1 session = 1 ticket]
```

## 6. `/qa` — cycle régression + wireframe + retrigger

```mermaid
flowchart TB
    Q0[step-00-init<br/>diff scope ticket/feature] --> Q1[step-01-collect]

    subgraph Q1[step-01-collect]
        REG{regression<br/>enabled?}
        WIRE{wireframe_check<br/>enabled?}
        REG -->|oui| RIMPACT[scope=impacted<br/>code-review-graph<br/>get_impact_radius]
        REG -->|oui| RFULL[scope=full<br/>test_command]
        REG -->|oui| RTESTS[scope=tests-only<br/>fallback]
        WIRE -->|oui| PLAY[Playwright MCP<br/>screenshots]
        PLAY --> DIFF[structural-diff<br/>vs Frame0 PNG]
    end

    Q1 --> Q2[step-02-interpret<br/>code-reviewer-qa subagent<br/>+ flaky detection]
    Q2 --> Q3{regression=pass<br/>ET wireframe=pass<br/>ET severity OK?}
    Q3 -->|non| FIX[dev agent applique<br/>qa_feedback_md]
    FIX --> AMEND[Amend commit ticket<br/>git commit --amend]
    AMEND --> Q1
    Q3 -->|oui| Q4{retrigger_review?<br/>+ fixes appliqués?}
    Q4 -->|oui| RETRIG[Re-run 3 reviewers<br/>/develop Phase 2<br/>1 retrigger max]
    Q4 -->|non| Q5[step-05-finish<br/>update ticket<br/>qa-validated]
    RETRIG --> Q5
```

## 7. États feature (machine à états)

```mermaid
stateDiagram-v2
    [*] --> defined: /define
    defined --> ticketed: /ticket
    ticketed --> wireframed: /wireframe (UI feature)
    ticketed --> developed: /develop (no UI)
    wireframed --> developed: /develop
    developed --> qa-validated: /qa
    qa-validated --> [*]: ship

    defined --> defined: /define -r (resume)
    ticketed --> ticketed: /ticket -r
    wireframed --> wireframed: /wireframe -r
    developed --> developed: /develop -r
```

## 8. Mode flags matrix

```mermaid
flowchart LR
    FLAGS[Flags transverses]
    FLAGS --> A[-a<br/>autonomous<br/>ask-or-default défauts]
    FLAGS --> I[-i<br/>interactive strict]
    FLAGS --> R[-r task-id<br/>resume partial-match]
    FLAGS --> E[-e / economy_mode<br/>parallel=1<br/>cycles=1]
    FLAGS --> DR[--dry-run<br/>read-only<br/>combinable -a]
    FLAGS --> S[-s save mode<br/>persist intermediate]
    FLAGS --> B[-b browse-only<br/>no execute]
```

## 9. MCP dependencies graph

```mermaid
flowchart LR
    subgraph REQ["Required (fail-fast)"]
        AFF[affine-mcp-server]
    end
    subgraph OPT["Optional (warn + fallback)"]
        F0[frame0-mcp-server]
        CRG[code-review-graph]
        PW[playwright-mcp]
    end
    subgraph CLI["CLI fallback"]
        GH[gh]
        GL[glab]
        JIRA[jira]
    end

    DEFINE[/define/] --> AFF
    TICKET[/ticket/] --> AFF
    TICKET --> CLI
    WIREFRAME[/wireframe/] --> AFF
    WIREFRAME --> F0
    DEVELOP[/develop/] --> CRG
    DEVELOP --> CLI
    QA[/qa/] --> CRG
    QA --> PW
```

## 10. Fail strategies (`/develop`)

```mermaid
flowchart TB
    MAX[review_cycles_max atteint] --> STRAT{fail_strategy}
    STRAT --> NT[next-ticket<br/>skip + log severities<br/>continue loop]
    STRAT --> ST[stop<br/>dump feedback<br/>progress.md]
    STRAT --> RT[retry max 1<br/>re-run Phase 1<br/>+ retry_strategy_hint]
    RT --> RTOK{retry OK?}
    RTOK -->|oui| DONE([Commit + sync])
    RTOK -->|non| FB{--retry-fallback}
    FB -->|next-ticket| NT
    FB -->|stop default| ST
```
