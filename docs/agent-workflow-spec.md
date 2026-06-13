# Claude Code Agent Workflow Spec

## Overview

A multi-agent system for autonomously picking up, planning, and implementing development tasks. The system is orchestrated by a **Majordomo agent** that runs on a schedule, evaluates work across projects, and launches **worker agents** to execute implementation tasks. A separate **planning agent** handles ticket grooming through an iterative human Q&A loop.

For repo structure, see [`GETTING_AROUND.md`](GETTING_AROUND.md). For branching model and task prioritization, see [`WORKFLOWS.md`](WORKFLOWS.md). For planned future work, see [`FUTURE_WORK.md`](FUTURE_WORK.md).

---

## Current Capabilities

### GH Issue Ingestion

Majordomo polls GitHub Issues on a schedule and creates beads tasks (Story + Plan) for each new Issue matching the allowlist in `shared/config.yaml`. Issues with `backlog` or `skip` labels are skipped. A `beads-ingested` label is applied to each Issue as an idempotency gate.

### Planning Agent Loop

Majordomo identifies open Plan beads tasks and triggers the planning agent Jenkins job. The planning agent researches the task, and either posts questions or produces a spec doc PR. Humans answer questions and approve spec docs via PR review. Before launching a planning agent, Majordomo checks `bd ready` for higher-priority implementation tasks and defers planning if one exists (planning priority guard).

### Plan Approval Spinoff

When a Plan bead is approved (spec PR merged), Majordomo reads the spec doc from the feature branch and creates one beads Stage task per `## Stage N:` section. Tasks are created in stage order and wired with blocking dependencies (stage N depends on N−1) so `bd ready` surfaces them in sequence.

### Task Prioritization & Worker Selection

Unblocked, unclaimed Stage tasks are surfaced by `bd ready`. Majordomo selects a worker target by excluding tasks whose Epic has a Stage sibling `in_progress`, then ranking by: continuity (Epic with at least one Stage task already closed) → Epic priority label (P0 > P1 > P2 > unlabelled). Beads creation order implicitly reflects stage sequence since tasks are created in order during Plan Approval Spinoff.

### Worker Agent

Workers branch from the current feature branch tip, implement the task, and open a PR to the feature branch. Before implementing the first stage of an Epic, the worker merges the base branch into the feature branch to avoid drift.

### PR Sync

Majordomo closes the corresponding beads Stage task when implementation PRs are merged.

### Feature → Main PRs

When all Stage tasks of an Epic are closed, Majordomo opens a feature→main PR. Before doing so, it reviews planning and research documents for context worth preserving, updates general docs as appropriate, then deletes `docs/planning/<EPIC_KEY>-spec.md` and `docs/research/<EPIC_KEY>/` from the feature branch so planning artifacts do not land on the base branch.

### Beads Task Coordination

`bd` (beads) serves as the agent-facing task coordination layer. It uses `Story:` / `Plan:` / `Stage N:` bead titles, exposes a dependency graph, and provides `bd ready` for task selection. Beads state is stored in a local Dolt DB and synced to the git remote via `refs/dolt/data`.

### Stale Task Sweep

A dedicated Jenkins pipeline (`minordomo-sweep/Jenkinsfile`) runs `shared/sweep-stale-tasks.sh` on a cron schedule (every 4 hours). It detects beads tasks that have been `in_progress` for more than 12 hours and resets them to `open`, covering both worker and planning agent tasks. Tasks with an open PR are skipped — they are actively in review, not orphaned. Before resetting each stale task, the sweep script attempts to post a comment on the associated GitHub Issue explaining the reset; comment failures are logged but do not block the reset. The job exits 0 even when some tasks encounter errors (partial success is better than aborting the sweep).

### Documentation Librarian

A dedicated Jenkins pipeline (`minordomo-librarian/Jenkinsfile`) runs daily on a cron schedule (`H H * * *`). It detects and repairs documentation drift in `docs/**/*.md`, `README.md`, and `CLAUDE.md` (excluding `docs/research/`, `docs/planning/`, and `docs/suggestions/`). Drift detection covers two types: **structural drift** (references to files or scripts that no longer exist; newly added files not yet documented) and **content drift** (descriptions that no longer match current code behavior). The Librarian also reads suggestion files written by pipeline agents to `docs/suggestions/`, integrates them into the appropriate documentation files, and deletes the suggestion files after integrating them. If any changes are needed, it creates a `librarian/YYYY-MM-DD` branch, commits all changes, pushes, and opens a PR to `main`. If no changes are needed or an open librarian PR already exists, it exits cleanly without creating a PR.

### Token Usage Reporting

`shared/report-token-usage.py` summarises input/cache/output tokens and cost per job, written to the Jenkins build log.

---

## Majordomo Run Sequence (Steps 1–9)

The full step-by-step instructions live in `majordomo/system-prompt.md`. Summary:

1. Load config from `shared/config.yaml`
2. Ingest new GH Issues → create beads Planning Tasks
3. Sync PR state → close beads Stage tasks for merged implementation PRs
4. Check for open Planning Tasks → launch planning agent (subject to planning priority guard)
5. Plan Approval Spinoff → create beads Stage tasks from approved spec docs; wire dependency chain
6. *(reserved)*
7. *(reserved)*
8. Select top ready Stage task via `bd ready` → launch worker
9. Open feature→main PRs for Epics with all Stage tasks closed (includes doc review/cleanup)
