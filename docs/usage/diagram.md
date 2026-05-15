# Workflow diagrams

Visual Mermaid diagrams. Global view + per-skill zooms + variants.

## 1. Global view (5-skill chain)

```mermaid
flowchart LR
    U([User]) -->|product idea| DEFINE
    DEFINE[/define/] -->|global PRD + feature<br/>AFFiNE| TICKET
    TICKET[/ticket/] -->|tickets push<br/>JIRA/GH/GL| WF{UI feature?}
    WF -->|yes| WIREFRAME[/wireframe/]
    WF -->|no| DEVELOP
    WIREFRAME -->|Frame0 wireframes<br/>+ AFFiNE gallery| DEVELOP[/develop/]
    DEVELOP -->|atomic commits<br/>+ PR/MR| QA[/qa/]
    QA -->|validated| END([Ship])

    classDef skill fill:#2d3748,stroke:#4a5568,color:#fff
    class DEFINE,TICKET,WIREFRAME,DEVELOP,QA skill
```

## 2. Storage & sources of truth

```mermaid
flowchart TB
    subgraph LOCAL[".snap/ (local cache)"]
        IDX[index.md]
        FEAT[features/NN-slug/]
        FEAT --> META[manifest.json]
        FEAT --> TIX[tickets.json]
        FEAT --> PROG[progress.json]
        FEAT --> WIRES[wireframes/]
    end

    subgraph EXT["Sources of truth (external)"]
        AFFINE[(AFFiNE / Notion<br/>v0.2: PRD archive + Functional doc<br/>{domain}/{journey})]
        PLAT[(Tickets platform<br/>JIRA/GH/GL)]
        FRAME[(Frame0<br/>shapes + PNG)]
        GIT[(Git repo<br/>branches + commits)]
    end

    META -.prd.page_id.-> AFFINE
    TIX -.platform IDs.-> PLAT
    WIRES -.frame0_page_id.-> FRAME
    META -.branch_name.-> GIT
```

## 3. `/define` — interactive flow

```mermaid
flowchart TB
    S0[step-00-init] --> DETECT{has_codebase?}
    DETECT -->|yes| S1[step-01-discover<br/>2-4 parallel agents<br/>explore-codebase]
    DETECT -->|no| GREEN[green_field=true<br/>spawn 2 agents:<br/>competitors + UX refs]
    S1 --> S2[step-02-vision<br/>progressive AskUserQuestion]
    GREEN --> S2
    S2 --> S3[step-03-features<br/>list + MoSCoW prioritization]
    S3 --> S4[step-04-render<br/>v0.2: per-feature PRD only]
    S4 --> S5[step-05-publish<br/>v0.2: PRD archive page<br/>+ domain/journey lookup-or-create]
```

## 4. `/develop` standalone — 2 phases + review cycle

```mermaid
flowchart TB
    INIT[step-00-init<br/>+ step-01-fetch<br/>+ step-02-prepare<br/>idempotent branch]

    INIT --> P1[Phase 1: Code]
    subgraph P1[Phase 1: Code]
        A[analyze<br/>impact_radius]
        P[plan<br/>A/P/C menu]
        E[execute<br/>Edit/Write]
        V[validate<br/>typecheck/lint/test]
        A --> P --> E --> V
        V -.fail max 3.-> E
    end

    P1 --> P2[Phase 2: Parallel reviews]
    subgraph P2[Phase 2: Parallel reviews]
        BATCH[1 message<br/>3 parallel Agent calls]
        BATCH --> RT[snap-code-reviewer-technical]
        BATCH --> RF[snap-code-reviewer-functional]
        BATCH --> RS[snap-code-reviewer-security]
        RT --> AGG{all severity<br/>< threshold?}
        RF --> AGG
        RS --> AGG
        AGG -->|no| FIX[dev agent applies<br/>aggregated_feedback]
        FIX --> BATCH
        AGG -->|yes| OK([Phase 2 OK])
    end

    P2 --> COMMIT[Atomic commit<br/>1 ticket = 1 commit<br/>amend if fixes]
    COMMIT --> SYNC[step-04-sync<br/>push + PR + update ticket]
    SYNC --> FIN[step-05-finish<br/>suggest /qa]

    AGG -.max cycles reached.-> STRAT{fail_strategy}
    STRAT -->|next-ticket| FIN
    STRAT -->|stop| STOP([Stop])
    STRAT -->|retry max 1| P1
```

## 5. `/develop` loop modes (3 variants)

```mermaid
flowchart LR
    ARG[<arg>] --> MATCH{format?}
    MATCH -->|ticket-id| STD[Standalone<br/>1 ticket = 1 cycle]
    MATCH -->|NN-kebab| LOOP{--loop=?}
    LOOP -->|none| ASK[AskUserQuestion<br/>session or daemon?]
    LOOP -->|session| SESS[Sequential loop<br/>same session<br/>step-03b]
    LOOP -->|daemon| DAEMON[Generates daemon.sh<br/>step-03c<br/>user runs manually]

    SESS --> ITER[For each ticket:<br/>step-03a Phase 1+2<br/>+ atomic commit]
    ITER --> NEXT{remaining<br/>tickets?}
    NEXT -->|yes| ITER
    NEXT -->|no| PUSH[Push branch in bulk<br/>step-04-sync]

    DAEMON --> MANUAL[bash daemon.sh -n 20<br/>external loop<br/>1 session = 1 ticket]
```

## 6. `/qa` — regression + wireframe + retrigger cycle

```mermaid
flowchart TB
    Q0[step-00-init<br/>ticket/feature diff scope] --> Q1[step-01-collect]

    subgraph Q1[step-01-collect]
        REG{regression<br/>enabled?}
        WIRE{wireframe_check<br/>enabled?}
        REG -->|yes| RIMPACT[scope=impacted<br/>code-review-graph<br/>get_impact_radius]
        REG -->|yes| RFULL[scope=full<br/>test_command]
        REG -->|yes| RTESTS[scope=tests-only<br/>fallback]
        WIRE -->|yes| PLAY[Playwright MCP<br/>screenshots]
        PLAY --> DIFF[structural-diff<br/>vs Frame0 PNG]
    end

    Q1 --> Q2[step-02-interpret<br/>code-reviewer-qa subagent<br/>+ flaky detection]
    Q2 --> Q3{regression=pass<br/>AND wireframe=pass<br/>AND severity OK?}
    Q3 -->|no| FIX[dev agent applies<br/>qa_feedback_md]
    FIX --> AMEND[Amend ticket commit<br/>git commit --amend]
    AMEND --> Q1
    Q3 -->|yes| Q4{retrigger_review?<br/>+ fixes applied?}
    Q4 -->|yes| RETRIG[Re-run 3 reviewers<br/>/develop Phase 2<br/>1 retrigger max]
    Q4 -->|no| Q5[step-05-finish<br/>update ticket<br/>qa-validated]
    RETRIG --> Q5
```

## 7. Feature states (state machine)

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
    FLAGS[Cross-cutting flags]
    FLAGS --> A[-a<br/>autonomous<br/>ask-or-default defaults]
    FLAGS --> I[-i<br/>strict interactive]
    FLAGS --> R[-r task-id<br/>partial-match resume]
    FLAGS --> E[-e / economy_mode<br/>parallel=1<br/>cycles=1]
    FLAGS --> DR[--dry-run<br/>read-only<br/>combinable with -a]
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
    MAX[review_cycles_max reached] --> STRAT{fail_strategy}
    STRAT --> NT[next-ticket<br/>skip + log severities<br/>continue loop]
    STRAT --> ST[stop<br/>dump feedback<br/>progress.json]
    STRAT --> RT[retry max 1<br/>re-run Phase 1<br/>+ retry_strategy_hint]
    RT --> RTOK{retry OK?}
    RTOK -->|yes| DONE([Commit + sync])
    RTOK -->|no| FB{--retry-fallback}
    FB -->|next-ticket| NT
    FB -->|stop default| ST
```
