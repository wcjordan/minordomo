# Research: Planning Agent Closes Its Own Bead (minordomo-3pt)

## Root Cause

The planning agent's `system-prompt.md` does not have an explicit "do not close the bead" instruction. Claude follows the beads CLAUDE.md session close protocol, which says to run `bd close <id>` for completed issues. Since the planning task is "complete" from Claude's perspective when the PR is opened, it closes the bead.

## Impact

Majordomo Step 6 (`Plan Approval Spinoff`) queries only `--status=in_progress` Plan beads. A closed bead is invisible to Step 6, so implementation tasks are never created.

## Evidence

- `minordomo-1tk.1` was closed by the planning agent with reason "Spec written and PR opened at ..." — no such `bd close` instruction exists in the system prompt.

## Fix

In `minordomo-plan/system-prompt.md`, in the Spec Path section (after step 4 "Open a PR"), add an explicit instruction:

> **Do NOT close the beads task.** Leave it `in_progress`. Majordomo Step 6 detects the merged PR, creates implementation tasks, and closes the Plan bead — the bead must remain `in_progress` for that flow to work.

## Related Files

- `minordomo-plan/system-prompt.md` — only file that needs changing
- `majordomo/system-prompt.md` Step 6 — the consumer of in_progress Plan beads
- `test/validate-prompts.py` — static validation; no changes needed
