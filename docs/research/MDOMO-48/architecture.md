# MDOMO-48 Research: Task Selection Enhancement

## GitHub Issue Summary

Two bugs in the Majordomo task selection algorithm:

1. **Planning tasks preempt higher-priority implementation tasks** — a P2 planning task will launch a planning agent even when P0/P1 implementation tasks are ready, because Step 5 (planning selection) always runs before Step 8 (worker selection) and sets `planning_agent_launched: true`, which causes Step 8 to be skipped.

2. **Wrong ranking criterion order in Step 8** — implementation tasks are sorted by `has_done_siblings` first (continuity), then `priority_order`. This means a P1 epic with some Done siblings ranks higher than a P0 epic with no Done siblings, violating the intent that P0 always beats P1.

The issue also asks to consider how Beads will change prioritization — if easier to use Beads, do so.

---

## Relevant Files

- `majordomo/system-prompt.md` — Steps 5 and 8 contain the task selection logic
- `docs/WORKFLOWS.md` — Documents the prioritization rules (partially outdated)

---

## Current Behavior: Step 5 (Planning Task Selection)

Algorithm in `majordomo/system-prompt.md`:

1. If any planning task is In Progress → skip, set `planning_agent_launched: false`
2. Query Jira for planning tasks in Open or Ready status
3. For each candidate: fetch parent Epic, check `needs-input` label on linked GH Issue
4. Pick highest-priority eligible task (by Epic priority label P0 > P1 > P2, then Jira rank)
5. Transition to In Progress and trigger `minordomo-plan` Jenkins job
6. Set `planning_agent_launched: true`

**BUG**: No comparison against available implementation task priorities. A P2 planning task will always preempt P0 implementation work.

---

## Current Behavior: Step 7 (Promote to Ready) — REMOVED

Step 7 was removed in "Stage 5 of the Jira→beads migration." It previously promoted Open Implementation Tasks to Ready status in Jira when:
1. All prior siblings (lower Jira rank) are Done
2. No sibling at any rank is In Progress or In Review

The removal note says: "The beads dependency graph created in Step 6 means `bd ready` surfaces only tasks with no open blockers — no explicit promotion step is needed. Jira's `Ready` status is populated by the worker agent itself when it picks up a task."

**IMPLICATION**: Step 8 currently queries for Jira "Ready" tasks, but nothing promotes tasks to Ready anymore. The intent is that Step 8 should use `bd ready` as the eligibility gate and handle the Jira status transitions itself.

---

## Current Behavior: Step 8 (Worker Selection)

Algorithm in `majordomo/system-prompt.md`:

1. Skip if `planning_agent_launched: true`
2. Run `bd ready --json | jq '[.[] | select(.title | startswith("Plan:") | not)]'` — **INFORMATIONAL ONLY**
3. Query Jira for implementation tasks in status **Ready** (affected by Step 7 removal)
4. Build candidate list: for each Ready task, fetch parent Epic (priority, rank), check needs-input, check for In Progress/In Review siblings
5. Rank candidates:
   - **1st**: `has_done_siblings` (true first — continuity heuristic) ← **BUG: should be 2nd**
   - **2nd**: `priority_order` (0=P0, 1=P1, 2=P2, 3=other) ← **BUG: should be 1st**
   - **3rd**: `epic_rank` (ascending lexicographic)
6. Transition selected task to In Progress
7. Claim corresponding beads subtask
8. Trigger worker Jenkins job

---

## Beads Dependency Graph (Step 6)

When a Planning Task is Approved, Majordomo (Step 6) creates beads subtasks and wires them:

```bash
bd create "Stage N: <title>" --parent "$BEADS_PLAN_ID" --json | jq -r '.id'
bd dep add "$BEADS_STAGE_N_ID" "$BEADS_STAGE_N_MINUS_1_ID"
```

This means `bd ready --json` naturally surfaces only the next unblocked stage for each Epic. Stages are blocked until previous stages complete in beads.

**NOTE**: Beads implementation subtasks are created WITHOUT explicit `--priority`. They may inherit priority from parent or have no priority set.

---

## Proposed Fixes

### Fix 1: Reorder Step 8 ranking criteria (priority-first)

Change:
```
Sort by: has_done_siblings desc, priority_order asc, epic_rank asc
```

To:
```
Sort by: priority_order asc, has_done_siblings desc, epic_rank asc
```

This ensures P0 always beats P1 regardless of continuity state.

### Fix 2: Use `bd ready` as Step 8 eligibility gate

Replace Jira "Ready" query with:
1. `bd ready --json` filtered to non-planning tasks → eligibility signal
2. Cross-reference with Jira (query Open OR Ready tasks)  
3. On dispatch: transition Open → Ready → In Progress (maintains worker's Ready-check in Step 1)

This completes the "Stage 5 beads migration" intent and fixes Step 7 removal gap.

### Fix 3: Planning task priority guard in Step 5

Before launching planning agent:
1. Get eligible implementation tasks via `bd ready --json` (non-planning only)
2. Map to Jira tasks, fetch epic priorities
3. Find best implementation priority available
4. Only launch planning agent if planning task's epic priority is strictly BETTER (lower number) than best implementation priority
5. If implementation tasks are same priority or better: skip planning agent, let Step 8 handle it
