# Implementation Plan: Planning agent closes its own bead, breaking Majordomo Step 6 spinoff

## Overview

The planning agent (`minordomo-plan`) closes its own beads task upon success because the CLAUDE.md session close protocol instructs Claude to close completed tasks. The system prompt lacks an explicit "do not close" guard. This breaks Majordomo Step 6, which searches for `in_progress` Plan beads to detect merged PRs and create implementation tasks.

The fix is a targeted addition to `minordomo-plan/system-prompt.md`: an explicit instruction in the Spec Path that the beads task must remain `in_progress` after the planning agent exits successfully.

---

## Stage 1: Add "do not close" instruction to planning agent system prompt

### Description

Add an explicit instruction to the Spec Path in `minordomo-plan/system-prompt.md` that tells the planning agent it must NOT close its own beads task. The instruction should explain why: the bead must stay `in_progress` so Majordomo Step 6 can detect the merged plan PR and create implementation tasks.

The instruction should be placed after step 4 (Open a PR) and before step 5 (Emit the run log and exit 0) in the Spec Path section. It should be clearly highlighted — e.g., a bold warning — so it is not overlooked.

Exact text to add as a new step 5 in the Spec Path (shift existing step 5 to step 6):

```
5. **Do NOT close the beads task.** Leave it `in_progress`. Majordomo Step 6 detects
   the merged plan PR, creates implementation tasks, and closes the Plan bead — the
   bead must remain `in_progress` for that detection to work.
```

### Acceptance Criteria

- `minordomo-plan/system-prompt.md` contains an explicit instruction (in the Spec Path) that the planning agent must NOT close the beads task after opening the PR
- The instruction explains that the bead must stay `in_progress` for Majordomo Step 6 to function
- `make test` passes (shellcheck, bats, validate-prompts.py all green)
- The Questions Path is unchanged (it already resets the bead to open, which is correct behavior)
