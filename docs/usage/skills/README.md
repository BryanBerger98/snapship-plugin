# 🎯 Skills

One usage doc per `/snap:*` command: flags, pipeline, outputs.

## Core workflow

| Skill                            | Role                                                            |
| -------------------------------- | --------------------------------------------------------------- |
| [`/snap:init`](init.md)          | Bootstrap workspace (config + `.snap/`). Once per project.       |
| [`/snap:define`](define.md)      | Interactive PRD brainstorm — product + features.                 |
| [`/snap:ticket`](ticket.md)      | Break a PRD into platform-fit tickets.                           |
| [`/snap:wireframe`](wireframe.md) | Multi-screen low-fi wireframes linked to tickets.               |
| [`/snap:design`](design.md)      | Optional hi-fi mockups for a ticket / feature.                   |
| [`/snap:develop`](develop.md)    | Implement ticket(s). 3 reviewers, atomic commits, PR.            |
| [`/snap:qa`](qa.md)              | Runtime validation: regression scope + Playwright wireframe diff. |

## Documentation utilities

| Skill                              | Role                                                          |
| ---------------------------------- | ------------------------------------------------------------- |
| [`/snap:doc-import`](doc-import.md) | Import existing docs into the SnapShip hierarchy. One-shot.  |
| [`/snap:doc-update`](doc-update.md) | Refresh the living functional doc after a feature ships.     |

---

> Need the big picture? → [Getting started](../getting-started.md) · [Diagram](../diagram.md)
