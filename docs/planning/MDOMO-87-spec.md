# Implementation Plan: Extract PR Merge Check to shared/check-pr-merged.sh (MDOMO-87)

## Stage 1: Create check-pr-merged.sh, add bats tests, and update majordomo call sites

### Description

Create `shared/check-pr-merged.sh` that encapsulates the repeated `gh pr list --state merged` check. The script accepts `<repo> <epic_key> <beads_task_id>` as positional arguments, exits 0 if a merged PR exists (and prints the PR number to stdout), and exits 1 if not. Propagates `gh` failures via `set -euo pipefail`.

Add bats tests in `test/bats/check-pr-merged.bats` covering:
- Merged case: exits 0 and prints PR number
- Not-merged case: exits 1 and produces no output
- Wrong argument count: exits non-zero without calling `gh`

Replace the three identical inline `gh pr list --state merged --json number` blocks in `majordomo/system-prompt.md` (Step 4 Stage tasks, Step 4 Plan tasks, Step 6 Plan Approval Spinoff) with calls to `shared/check-pr-merged.sh`.

`make test` (shellcheck + bats) must pass after this change.

### Acceptance Criteria

- `shared/check-pr-merged.sh` exists, is executable, and passes shellcheck
- Script exits 0 and prints the PR number when a merged PR is found; exits 1 silently when none found; exits non-zero with a usage message when called with wrong argument count
- `test/bats/check-pr-merged.bats` exists and all tests pass
- No `gh pr list.*--state merged` literal patterns remain in `majordomo/system-prompt.md`
- `make test` passes
