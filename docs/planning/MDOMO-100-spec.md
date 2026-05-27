# Implementation Plan: Extract needs-input flow to shared/apply-needs-input.sh

Epic: MDOMO-100  
GH Issue: https://github.com/wcjordan/minordomo/issues/145

## Overview

The "needs-input" flow (apply label + post comment + reset beads task) is duplicated in the planning agent and worker agent prompts. This plan extracts it into `shared/apply-needs-input.sh` and updates both prompts to call it.

---

## Stage 1: Create shared/apply-needs-input.sh with unit tests

### Description

Create `shared/apply-needs-input.sh` that encapsulates the three-step needs-input protocol:
1. Apply the `needs-input` label to a GitHub issue
2. Post a comment to that issue
3. Reset the beads task status back to `open` via `shared/beads-write.sh`

The script takes four positional arguments: `<repo> <issue_number> <beads_task_id> <comment_body>`. It exits non-zero and logs to stderr identifying the failed step if any step fails.

Also create `test/bats/apply-needs-input.bats` covering:
- Happy path: all three gh/bd calls succeed
- Failure on label step: gh issue edit fails → exits non-zero
- Failure on comment step: gh issue comment fails → exits non-zero
- Failure on beads reset step: bd/beads-write fails → exits non-zero
- Missing argument: exits non-zero without calling gh or bd

Run `make test` to confirm all tests pass.

### Acceptance Criteria
- `shared/apply-needs-input.sh` exists and is executable
- Script exits 0 when all three operations succeed
- Script exits non-zero and prints a descriptive stderr message identifying the failed step when any operation fails
- `test/bats/apply-needs-input.bats` exists and all its tests pass
- `make test` passes with no regressions

---

## Stage 2: Update system prompts to use apply-needs-input.sh

### Description

Replace the inline three-step needs-input sequence in both system prompts with a single call to `shared/apply-needs-input.sh`.

**Planning agent** (`minordomo-plan/system-prompt.md`), Questions Path:
- Replace steps 1 (label) and 2 (comment) with one call:
  ```bash
  shared/apply-needs-input.sh minordomo "${gh_issue_number}" "${BEADS_TASK_ID}" "<numbered question list>"
  ```
- Remove the now-redundant step 3 (`shared/beads-write.sh update ... --status open`) since `apply-needs-input.sh` handles it

**Worker agent** (`minordomo-step/system-prompt.md`), Needs Input Flow:
- Replace steps 2 (label), 3 (comment), and 4 (beads reset) with one call:
  ```bash
  shared/apply-needs-input.sh "$REPO" "$GH_ISSUE_NUMBER" "${BEADS_TASK_ID}" "<clear explanation>"
  ```
- Step 1 (finding GH issue number via `shared/get-epic-key.sh`) remains unchanged

Also add `shared/apply-needs-input.sh` to `shared/pipeline-helpers.sh` documentation comment if one exists, or update CLAUDE.md if there is a list of shared scripts — check and update as needed.

Run `make test` to confirm prompt validation passes.

### Acceptance Criteria
- `minordomo-plan/system-prompt.md` Questions Path uses `shared/apply-needs-input.sh` instead of three separate commands
- `minordomo-step/system-prompt.md` Needs Input Flow uses `shared/apply-needs-input.sh` instead of three separate commands
- Neither prompt contains the old inline `gh issue edit ... --add-label needs-input` sequence
- `make test` passes with no regressions
