# Workflows

How work flows through the minordomo pipeline: Jira ticket hierarchy, status transitions, branching, spec documents, and task prioritization.

---

## Jira Ticket Hierarchy

```
Epic (linked to GH Issue)
└── Implementation Tasks  (one per stage from the approved plan)
```

- Epics are created by Majordomo when a new GH Issue is ingested (Step 3). Plan tasks exist in beads only (not Jira).
- Implementation Tasks are spun off by Majordomo when the Plan bead reaches `Approved` (Step 5). One task per `## Stage N:` section in the spec doc.
- Implementation tasks are leaf nodes — no further planning required. They become eligible for promotion once all prior sibling tasks are `Done`.

**Task identity:**
- Implementation Tasks: `issuetype = Task AND summary !~ "^Plan:"`

---

## Jira Status Flows

### Implementation Task

```
Open → Ready → In Progress → In Review → Done
```

| Status | Meaning |
|---|---|
| Open | Created; not yet promoted by Majordomo |
| Ready | Eligible and queued; Majordomo will launch a worker |
| In Progress | Worker agent is actively implementing |
| In Review | Worker opened PR; awaiting human review and merge |
| Needs Input | Worker encountered a blocker requiring human input |
| Done | Human merged PR; Majordomo auto-transitions on next run |

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
| closed | Plan approved; Majordomo spun off Implementation Tasks (Step 5) |

Plan tasks never appear in Jira. They live entirely in beads and are identified by the `Plan:` title prefix.

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
| in_progress | Claimed by Majordomo (Step 8) just before launching the worker |
| closed | Worker's PR was merged; Majordomo transitions on next run (Step 4) |

If the worker hits a blocker requiring human input, it applies the `needs-input` label to the GH Issue and moves the Stage bead back to `open` so it can be re-claimed once the human resolves the blocker. Stage tasks are identified by the `Stage N:` title prefix and mirror a Jira Implementation Task via `external_ref`.

---

## Branching Model

All merges across branches require a human-reviewed PR. Agents never merge directly.

```
<base_branch> (bootstrap by default)
└── feature/story-bead-id        (Epic/Story branch)
    ├── task/story-bead-id.0     (planning task; spec doc PR → feature/story-bead-id)
    ├── task/story-bead-id.1     (impl stage 1; PR → feature/story-bead-id)
    ├── task/story-bead-id.2     (impl stage 2; PR → feature/story-bead-id)
    └── task/story-bead-id.3     (impl stage 3; PR → feature/story-bead-id)
```

- **Feature branch** — created by the planning agent; holds the spec doc (`docs/planning/story-bead-id-spec.md`) during implementation; spec is deleted from the feature branch before the feature→main PR is opened
- **Task branches** — created by the agent at launch time, always branching from the current feature branch tip; named `task/<ticket-id>`
- **task → feature PRs** — opened by the agent on completion; reviewed and merged by human
- **feature → base PRs** — opened by Majordomo when all Implementation Tasks of an Epic are `Done`; reviewed and merged by human

Agents never pre-create branches. Branching at launch time ensures each agent starts from the latest feature branch tip, picking up the spec and any code changes from prior merged stages.

---

## Spec Documents

The implementation plan lives as a markdown file on the feature branch (`docs/planning/story-bead-id-spec.md`). It is created by the planning agent on its task branch and arrives on the feature branch when the planning PR is merged.

Each `## Stage N:` section in the spec yields one Jira Implementation Task. The stage number is not stored in the Jira title — only the text after `## Stage N:` is used. Stage ordering is determined by Jira rank (`customfield_10019`), which reflects creation order.

When a stage's implementation reveals necessary changes to the plan, the spec doc is updated and included in that stage's PR. The next stage's worker branches from the updated feature branch and reads the current spec.

Before opening the feature→main PR (Step 9), Majordomo first reviews the planning and research documents for context worth preserving, updating general docs (README.md, CLAUDE.md, GETTING_AROUND.md, and others) as appropriate. After updating docs, it deletes `docs/planning/<EPIC_KEY>-spec.md` and `docs/research/<EPIC_KEY>/` from the feature branch. Planning and research artifacts do not land on the base branch.

---

## Prioritization (Steps 6 & 7)

**Promoting to Ready (Step 6):** An Open Implementation Task is eligible for `Ready` if:
1. All prior siblings (lower Jira rank) are `Done`
2. No sibling at any rank is `In Progress` or `In Review`

At most one task per Epic can be promoted at a time (the second check ensures this).

**Selecting a worker target (Step 7):** From all `Ready` tasks, Majordomo excludes tasks whose Epic has a sibling `In Progress` or `In Review`, then ranks the remainder:
1. Tasks whose Epic has at least one Implementation Task already `Done` (continuity)
2. Epic priority label: `P0` > `P1` > `P2` > unlabelled
3. Epic Jira rank (`customfield_10019`, ascending lexicographic = manual ordering)

Majordomo launches at most one worker per run, and skips worker launch if a planning agent was launched that run.

**Planning agent priority guard (Step 5):** Before launching a planning agent, Majordomo checks whether any higher-priority implementation tasks are available in beads (`bd ready`). If the best unblocked, unclaimed implementation task has a strictly lower numeric priority (0=P0 best) than the selected planning task, the planning agent launch is deferred and Step 8 handles implementation work instead. Equal priorities or no beads-eligible implementation tasks → planning agent proceeds as normal.

Beads (`bd ready`) is used here rather than Jira `status = Ready` because Step 7 (Promote to Ready) is a no-op in the beads migration — Jira implementation tasks remain in `Open` status until a worker claims them. Querying Jira for `status = Ready` would almost always return zero results, making the guard ineffective. `bd ready` correctly surfaces all unblocked, unclaimed implementation tasks regardless of their Jira status.

---

## Future Directions

- **GH Actions migration** — when ready, Jenkinsfile logic moves to workflow YAML; Majordomo, planning agent, worker, and sweep job code remain unchanged
- **Parallel workers** — Majordomo launches N workers; `In Progress` transition is the atomic claim
- **WIP commits** — if task failure rates or durations warrant it, introduce mid-task commits to reduce lost work on Jenkins crash
