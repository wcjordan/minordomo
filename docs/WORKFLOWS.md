# Workflows

How work flows through the minordomo pipeline: status transitions, branching, spec documents, and task prioritization.

---

## Beads Status Flows

### Plan Task

```
open → in_progress → closed
```

| Status | Meaning |
|---|---|
| open | Created by Majordomo (Step 3); available for a planning agent to claim |
| in_progress | Planning agent has claimed the task and is actively working |
| blocked | Waiting on a dependency (e.g. an upstream Plan task is not yet closed) |
| closed | Plan approved; Majordomo spun off Stage tasks (Step 6) |

Plan tasks live entirely in beads and are identified by the `Plan:` title prefix.

### Story

Story beads are container beads — they do not move through a status lifecycle. A Story bead is created `open` by Majordomo (Step 3) when a GH Issue is ingested and remains `open` throughout all planning and implementation work beneath it. Majordomo polls open Story beads (Step 9) to detect when all Stage children are closed and then opens the feature → base PR.

### Stage (Implementation Task)

```
open → in_progress → closed
         ↓
        open  (needs-input revert)
```

| Status | Meaning |
|---|---|
| open | Created by Majordomo (Step 6) when the Plan bead is approved; no blockers remain |
| blocked | Earlier Stage sibling is not yet closed; `bd ready` excludes this task |
| in_progress | Claimed by Majordomo (Step 8) just before launching the worker; in multi-step runs, also means awaiting PR review for stages completed earlier in the same run |
| closed | Worker's PR was merged; Majordomo transitions on next run (Step 4) |

If the worker hits a blocker requiring human input, it applies the `needs-input` label to the GH Issue and moves the Stage bead back to `open` so it can be re-claimed once the human resolves the blocker. Stage tasks are identified by the `Stage N:` title prefix.

---

## Branching Model

All merges across branches require a human-reviewed PR. Agents never merge directly.

```
<base_branch> (bootstrap by default)
└── feature/story-bead-id        (Epic/Story branch)
    ├── task/story-bead-id.0     (planning task; spec doc PR → feature/story-bead-id)
    ├── task/story-bead-id.1     (impl stage 1; PR → feature/story-bead-id)
    │   └── task/story-bead-id.2 (impl stage 2; PR → task/story-bead-id.1)
    │       └── task/story-bead-id.3 (impl stage 3; PR → task/story-bead-id.2)
```

- **Feature branch** — created by the planning agent; holds the spec doc (`docs/planning/story-bead-id-spec.md`) during implementation; spec is deleted from the feature branch before the feature→main PR is opened
- **Task branches** — created at launch time; named `task/<ticket-id>`
  - Stage 1 branches from the current feature branch tip
  - Stages 2+ branch from the previous stage's task branch (`task/<prev-id>`), forming a stacked chain
- **task → feature/task PRs** — opened by the agent on completion; reviewed and merged by human; Stage 1 targets the feature branch, Stage 2+ target the previous stage's task branch
- **feature → base PRs** — opened by Majordomo when all Stage tasks of an Epic are closed; reviewed and merged by human

Agents never pre-create branches. The `minordomo-steps` job runs all stages in a single Jenkins run, stacking each stage's branch on the previous one so each PR shows only that stage's diff when reviewed in order.

---

## Spec Documents

The implementation plan lives as a markdown file on the feature branch (`docs/planning/story-bead-id-spec.md`). It is created by the planning agent on its task branch and arrives on the feature branch when the planning PR is merged.

Stage ordering is determined by the beads dependency chain wired by Majordomo during Plan Approval Spinoff (Step 6k); each stage N depends on stage N−1.

When a stage's implementation reveals necessary changes to the plan, the spec doc is updated and included in that stage's PR. In multi-step runs, the next stage's branch is stacked on the previous stage's task branch, so spec updates arrive via the stacked merge chain rather than directly from the feature branch.

Before opening the feature→main PR (Step 9), Majordomo first reviews the planning and research documents for context worth preserving, updating general docs (README.md, CLAUDE.md, GETTING_AROUND.md, and others) as appropriate. After updating docs, it deletes `docs/planning/<EPIC_KEY>-spec.md` and `docs/research/<EPIC_KEY>/` from the feature branch. Planning and research artifacts do not land on the base branch.

---

## Prioritization (Step 8)

**Selecting a worker target (Step 8):** `bd ready` surfaces all unblocked, unclaimed Stage tasks. Majordomo excludes tasks whose Epic has a Stage sibling `in_progress`, then ranks the remainder:
1. Tasks whose Epic has at least one Stage task already closed (continuity)
2. Epic priority label: `P0` > `P1` > `P2` > unlabelled

Majordomo launches at most one worker per run via `minordomo-steps` (which runs all stages for the selected Epic in sequence), and skips worker launch if a planning agent was launched that run. The `minordomo-step` job is retained for manual single-stage runs but is no longer triggered automatically by Majordomo.

**Planning agent priority guard (Step 5):** Before launching a planning agent, Majordomo checks whether any higher-priority implementation tasks are available in beads (`bd ready`). If the best unblocked, unclaimed implementation task has a strictly lower numeric priority (0=P0 best) than the selected planning task, the planning agent launch is deferred and Step 8 handles implementation work instead. Equal priorities or no beads-eligible implementation tasks → planning agent proceeds as normal.

Stage ordering and eligibility are entirely beads-based: `bd ready` surfaces only tasks with no open blockers (all prior Stage siblings closed). No explicit "Promote to Ready" step is needed — the beads dependency graph created during Plan Approval Spinoff (Step 6k) handles sequencing automatically.

---

## Future Directions

- **GH Actions migration** — when ready, Jenkinsfile logic moves to workflow YAML; Majordomo, planning agent, worker, and sweep job code remain unchanged
- **Parallel workers** — Majordomo launches N workers; `In Progress` transition is the atomic claim
- **WIP commits** — if task failure rates or durations warrant it, introduce mid-task commits to reduce lost work on Jenkins crash
