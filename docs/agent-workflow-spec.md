# Claude Code Agent Workflow Spec

## Overview

A multi-agent system for autonomously picking up, planning, and implementing development tasks. The system is orchestrated by a **Majordomo agent** that runs on a schedule, evaluates work across projects, and launches **worker agents** to execute implementation tasks. A separate **planning agent** handles ticket grooming through an iterative human Q&A loop.

For repo structure, see [`GETTING_AROUND.md`](GETTING_AROUND.md). For Jira status flows, branching model, and task prioritization, see [`WORKFLOWS.md`](WORKFLOWS.md). For planned future work, see [`FUTURE_WORK.md`](FUTURE_WORK.md).

---

## Current Capabilities

### GH Issue Ingestion

Majordomo polls GitHub Issues on a schedule and creates a Jira Epic + Planning Task for each new Issue matching the allowlist in `shared/config.yaml`. Issues with `backlog` or `skip` labels are skipped. A `jira-epic-created` label is applied to each Issue as an idempotency gate.

### Planning Agent Loop

Majordomo identifies open Planning Tasks, transitions them to In Progress, and triggers the planning agent Jenkins job. The planning agent researches the task, and either posts questions (→ Needs Input) or produces a spec doc PR (→ In Review). Humans answer questions via Jira comments and approve spec docs via PR review. Before launching a planning agent, Majordomo checks `bd ready` for higher-priority implementation tasks and defers planning if one exists (planning priority guard).

### Plan Approval Spinoff

When a Planning Task is approved, Majordomo reads the spec doc from the feature branch and creates one Jira Implementation Task per `## Stage N:` section. Implementation Tasks are created in stage order; Jira rank reflects stage sequence and is used for ordering.

### Task Prioritization & Ready Promotion

Majordomo promotes eligible Implementation Tasks from Open to Ready: a task is eligible when all prior siblings (lower Jira rank) are Done and no sibling is In Progress or In Review. At most one task per Epic can be Ready at a time. When selecting a worker target from all Ready tasks, Majordomo excludes tasks whose Epic has a sibling In Progress or In Review, then ranks by: continuity (Epic with at least one Implementation Task already Done) → Epic priority label (P0 > P1 > P2 > unlabelled) → Epic Jira rank.

### Worker Agent

Workers branch from the current feature branch tip, implementing the task, opening a PR to the feature branch, and transitioning the Jira ticket to In Review. Before implementing the first stage of an Epic, the worker merges the base branch into the feature branch to avoid drift.

### PR Sync

Majordomo auto-transitions Jira tickets when humans merge planning or implementation PRs.

### Feature → Main PRs

When all Implementation Tasks of an Epic are Done, Majordomo opens a feature→main PR. Before doing so, it reviews planning and research documents for context worth preserving, updates general docs as appropriate, then deletes `docs/planning/<EPIC_KEY>-spec.md` and `docs/research/<EPIC_KEY>/` from the feature branch so planning artifacts do not land on the base branch.

### Beads Task Coordination

`bd` (beads) serves as the agent-facing task coordination layer. It mirrors the Jira Epic → Story → Task hierarchy using `Story:` / `Plan:` / `Stage N:` bead titles, exposes a dependency graph, and provides `bd ready` for task selection. Beads state is stored in a local Dolt DB and synced to the git remote via `refs/dolt/data`.

### Token Usage Reporting

`shared/report-token-usage.py` summarises input/cache/output tokens and cost per job, written to the Jenkins build log.

---

## Majordomo Run Sequence (Steps 1–9)

The full step-by-step instructions live in `majordomo/system-prompt.md`. Summary:

1. Load config from `shared/config.yaml`
2. Ingest new GH Issues → create Jira Epics + Planning Tasks
3. Sync PR state → transition Jira tickets for merged PRs
4. Check for open Planning Tasks → launch planning agent (subject to planning priority guard)
5. Plan Approval Spinoff → create Implementation Tasks from approved spec docs
6. Promote eligible Implementation Tasks to Ready
7. Select top Ready task → launch worker
8. *(reserved)*
9. Open feature→main PRs for Epics with all Implementation Tasks Done (includes doc review/cleanup)
