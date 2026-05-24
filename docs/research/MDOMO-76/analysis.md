# MDOMO-76: Beads for planning tasks aren't getting closed — Research Notes

## Problem Statement

Plan beads (e.g., `Plan: <issue title>`) are not being automatically closed after implementation subtasks are spun out in Majordomo Step 6 (Plan Approval Spinoff).

## Evidence

From `.beads/issues.jsonl` and interaction log (PR #114 "Fix beads issues.jsonl"):

- `minordomo-tic.1` (Plan: Email me if a run fails) — NOT auto-closed; manually closed in PR #114
- `minordomo-7ny.1` (Plan: Remove docs/planning...) — NOT auto-closed; manually closed in PR #114
- `minordomo-856` (Plan: Use beads instead of Jira...) — currently open; Stage beads exist (spinoff ran but didn't close Plan bead)

Both `tic.1` and `7ny.1` had their Story beads correctly found (the story beads exist). Sub-step h succeeded. Sub-steps i–k ran (Stage beads were created). But sub-step l failed to close the Plan bead.

## Root Cause Analysis

### Root Cause 1: Contradictory note in Step 4

`majordomo/system-prompt.md` line 116:
> "The Plan bead remains open as a child of the Story bead after the spinoff."

This directly contradicts Step 6 sub-step l which explicitly closes the Plan bead. An LLM agent reading Step 4 may interpret "remains open after the spinoff" as a permanent instruction, causing it to skip or no-op in sub-step l.

### Root Cause 2: `bd list --json` may not include in_progress Plan beads

In Step 5, the Plan bead is claimed with `bd update "$BEADS_PLAN_ID" --claim`, moving it to `in_progress`. By the time Step 6 sub-step l runs, the Plan bead is `in_progress`. If `bd list --json` (without `--status` flag) doesn't return in_progress tasks, the lookup silently returns empty and the `if` block is skipped.

Evidence: The beads PRIME output lists `bd list --status=in_progress` as a separate command for "your active work", suggesting in_progress tasks are NOT in the default `bd list` output.

### Root Cause 3: Silent failure in sub-step l

Sub-step l has no `else` clause to log when the Plan bead is not found. The prompt says "log a per-epic warning" but the code block has no `else`, so Majordomo may write no logging and the failure is invisible in run logs.

## Key Code Locations

- Step 4 problematic note: `majordomo/system-prompt.md` line 116
- Step 5 Plan bead claim: `majordomo/system-prompt.md` lines 179–184
- Step 6 sub-step l: `majordomo/system-prompt.md` lines 233–240

## Historical Context

- PR #74 (`1fd13a6`): First added Plan bead closing — in Step 4 when PR merges
- PR #99 (`b972705`): Changed Step 4 to NOT close Plan bead; moved closing to Step 6 sub-step l; added confusing note "remains open after the spinoff"
- PR #114 (`d8c68fb`): Manual fix of issues.jsonl — closed the Plan beads that should have been auto-closed

## Proposed Fix

### File: `majordomo/system-prompt.md`

1. **Step 4, line 116**: Replace "The Plan bead remains open as a child of the Story bead after the spinoff." with "The Plan bead will be closed by Step 6 (Plan Approval Spinoff) after implementation subtasks are created."

2. **Step 6, sub-step l**: 
   - Change the `bd list --json` lookup to also search in_progress state (fallback)
   - Add an explicit `else` clause that logs the per-epic warning

### Fix for `minordomo-856`

The spinoff for this epic already ran (Jira task is Done). Step 6 won't re-process it. This Plan bead needs a one-time manual close. However, since Stage 8 and 9 are still in progress, the bead is arguably correctly reflecting ongoing work. It should be manually closed as cleanup after the main fix is in place.
