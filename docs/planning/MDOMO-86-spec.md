# MDOMO-86: Extract beads→epic key lookup to shared/get-epic-key.sh

## Overview

The four-step chain that derives a Jira EPIC_KEY from a beads task ID
(task → GH Issue URL → `gh issue view` → `Jira Epic:` comment regex)
appears inline in four places in `majordomo/system-prompt.md`, once in
`minordomo-step/system-prompt.md`, and once in `shared/setup-workspace.sh`.
This spec centralizes that logic into a single `shared/get-epic-key.sh` script,
then replaces every inline occurrence with a call to that script.

---

## Stage 1: Create shared/get-epic-key.sh with bats tests

### Description
Create `shared/get-epic-key.sh <beads_task_id> <repo>`. The script follows the chain: `bd show` → extract GH Issue URL (checking the task's own description first, then the parent's if absent) → `gh issue view --json comments` → regex for `Jira Epic: KEY`. It prints EPIC_KEY on the first output line and GH_ISSUE_NUMBER on the second, exits non-zero to stderr if any step fails, and passes shellcheck. Add a `test/bats/get-epic-key.bats` file that covers the happy path and each failure mode (no GH URL in description, no parent fallback, no matching comment).

### Acceptance Criteria
- `shared/get-epic-key.sh <beads_task_id> <repo>` prints EPIC_KEY on line 1 and GH_ISSUE_NUMBER on line 2 to stdout (bare values, no key= prefix)
- If GH Issue URL is absent from the task's own description, the script retries from the parent bead's description (same fallback logic as `shared/setup-workspace.sh` lines 56–59)
- Exits 1 with a message to stderr when: task not found, no GH Issue URL found after checking task and parent, or no `Jira Epic:` comment found
- Script is executable and passes `shellcheck shared/get-epic-key.sh` (verified by `make test`)
- `test/bats/get-epic-key.bats` covers: happy path (URL in task description), happy path (URL in parent description only), failure when no URL found, failure when no `Jira Epic:` comment found
- `make test` passes

---

## Stage 2: Refactor system prompts to use shared/get-epic-key.sh

### Description
Replace every inline EPIC_KEY derivation block in `majordomo/system-prompt.md` and `minordomo-step/system-prompt.md` with calls to `shared/get-epic-key.sh`. In `majordomo/system-prompt.md`: update Helper 2 (the prologue to Step 4) to show the `get-epic-key.sh` invocation pattern and update Steps 4c, 5c, Step 6 plan-approval block, Step 8, and Step 9 accordingly. In `minordomo-step/system-prompt.md`: replace the Needs Input Flow's three-line chain that derives `GH_ISSUE_NUMBER` with a single `get-epic-key.sh` call (capturing the second output line).

### Acceptance Criteria
- `majordomo/system-prompt.md` Helper 2 describes `shared/get-epic-key.sh` usage with the two-line capture pattern (EPIC_KEY from line 1, GH_ISSUE_NUMBER from line 2)
- The inline Python + bash EPIC_KEY derivation blocks in Step 9 of `majordomo/system-prompt.md` are replaced with `shared/get-epic-key.sh` calls
- `minordomo-step/system-prompt.md` Needs Input Flow uses `shared/get-epic-key.sh` to obtain GH_ISSUE_NUMBER rather than the three-step `bd show` chain
- `make test` passes (the prompt validator confirms `shared/get-epic-key.sh` exists as a referenced path)

---

## Stage 3: Refactor shared/setup-workspace.sh to use shared/get-epic-key.sh

### Description
Replace the inline EPIC_KEY derivation block in `shared/setup-workspace.sh` (lines 51–79) with a call to `shared/get-epic-key.sh`. The script's REPO is already known at that point, and the beads DB has been initialized by `bd bootstrap && bd dolt pull`, so the call is straightforward. Update `test/bats/setup-workspace.bats` to reflect the changed internal behavior (the mock `gh issue view` and `bd show` parent calls now route through `get-epic-key.sh`).

### Acceptance Criteria
- `shared/setup-workspace.sh` no longer contains the inline `bd show` parent chain + `gh issue view` + Python regex for EPIC_KEY; it calls `"$(dirname "${BASH_SOURCE[0]}")/get-epic-key.sh"` instead
- `EPIC_KEY` and `GH_ISSUE_NUMBER` (or `FEATURE_BRANCH` derived from it) are set correctly from the script's output
- `test/bats/setup-workspace.bats` tests still pass after the refactor
- `make test` passes
