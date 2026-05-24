# MDOMO-76: Beads for planning tasks aren't getting closed

## Epic Summary

Plan beads (e.g., `Plan: <issue title>`) created in Step 3 (Poll GitHub Issues) are not being automatically closed after Majordomo's Step 6 (Plan Approval Spinoff) creates the implementation subtask beads. The root cause is a contradictory note in Step 4 that tells the LLM agent the Plan bead "remains open after the spinoff," directly contradicting Step 6 sub-step l which explicitly closes the Plan bead. A secondary issue is that sub-step l has no `else` clause, making any failure completely silent in run logs.

## Root Cause

**Step 4, line 116** of `majordomo/system-prompt.md` currently reads:

> If the task was a Planning Task (summary starts with `"Plan:"`): do **not** close the beads planning task here. The Plan bead remains open as a child of the Story bead after the spinoff.

The phrase "remains open as a child of the Story bead **after the spinoff**" is semantically ambiguous — an LLM agent reading this instruction can correctly interpret it as a durable behavioral rule ("always leave Plan beads open"), causing it to no-op in sub-step l even though sub-step l explicitly says to close the Plan bead.

The `.beads/interactions.jsonl` log confirms Plan beads were in `open` status (not `in_progress`) immediately before manual closure in PR #114, meaning the lookup in sub-step l succeeds but the close is skipped due to this contradictory instruction.

## Stage 1: Fix Step 4 note and Step 6 sub-step l to correctly close Plan beads

### Description

Edit `majordomo/system-prompt.md` in two places:

1. **Step 4, line 116** — replace "The Plan bead remains open as a child of the Story bead after the spinoff." with a forward-reference that makes the lifecycle unambiguous: the Plan bead will be closed by Step 6 sub-step l, not here.

2. **Step 6, sub-step l** — add an explicit `else` clause that logs a per-epic warning when the Plan bead is not found by title, and add a success log entry when it is closed. The current code has a comment saying "log a per-epic warning" but no code that does so.

### Files Changed

- `majordomo/system-prompt.md`

### Exact Changes

#### Change 1 — Step 4, line 116

Replace:
```
      - If the task was a Planning Task (summary starts with `"Plan:"`): do **not** close the beads planning task here. The Plan bead remains open as a child of the Story bead after the spinoff.
```

With:
```
      - If the task was a Planning Task (summary starts with `"Plan:"`): do **not** close the beads planning task here. The Plan bead will be closed by Step 6 sub-step l after implementation subtasks are created.
```

#### Change 2 — Step 6, sub-step l (lines 233–240)

Replace:
```bash
   l. **Close the beads planning task** — now that subtasks and dependencies are wired, look up and close the Plan bead by the planning task's summary:
      ```bash
      BEADS_PLAN_ID=$(bd list --json | jq -r --arg title "<planning_task_summary>" '[.[] | select(.title == $title)] | first | .id // empty')
      if [ -n "$BEADS_PLAN_ID" ]; then
        bd close "$BEADS_PLAN_ID"
      fi
      ```
      If not found or `bd close` fails, log a per-epic warning and continue (the Jira task was already transitioned to Done in step g).
```

With:
```bash
   l. **Close the beads planning task** — now that subtasks and dependencies are wired, look up and close the Plan bead by the planning task's summary:
      ```bash
      BEADS_PLAN_ID=$(bd list --json | jq -r --arg title "<planning_task_summary>" '[.[] | select(.title == $title)] | first | .id // empty')
      if [ -n "$BEADS_PLAN_ID" ]; then
        bd close "$BEADS_PLAN_ID"
        # log per-epic: plan_bead_closed: <BEADS_PLAN_ID>
      else
        # log per-epic warning: plan_bead_not_found: <planning_task_summary>; do not abort — Jira task already transitioned in step g
      fi
      ```
      Whether closed or not found, always log the outcome so it is visible in the run log.
```

### Acceptance Criteria

- Step 4's note for Planning Tasks no longer says "remains open after the spinoff"; it now says the Plan bead will be closed by Step 6 sub-step l
- Step 6 sub-step l includes an explicit `else` clause that logs a per-epic warning (`plan_bead_not_found`) when the Plan bead is not found by title
- Step 6 sub-step l logs a success entry (`plan_bead_closed: <id>`) in the per-epic log when the Plan bead is successfully closed
- On the next Majordomo run that processes an Approved Planning Task, the corresponding Plan bead is closed and the closure is visible in the run log

### Out of Scope

- `minordomo-856` (Plan: Use beads instead of Jira for story tracking): this Plan bead's spinoff already ran and Step 6 will not re-process it. It needs a separate one-time manual close.
- Any change to `bd list` behavior or status filtering — the interactions log shows Plan beads remain in `open` status through spinoff, so the existing `bd list --json` query is sufficient.
