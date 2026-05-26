# Research: Extract PR Merge Check to shared/check-pr-merged.sh (MDOMO-87)

## Problem

The `gh pr list` PR merge check appears identically in 3 places in `majordomo/system-prompt.md`:

1. **Step 4 (Stage tasks)** — lines ~137–140: check if an implementation task's PR merged into `feature/<EPIC_KEY>`
2. **Step 4 (Plan tasks)** — lines ~154–157: check if a planning task's PR merged into `feature/<EPIC_KEY>`
3. **Step 6 (Plan Approval Spinoff)** — lines ~262–265: check if a plan PR merged before creating implementation tasks

All three follow the same pattern:
```bash
gh pr list --repo wcjordan/<repo> \
  --base feature/<EPIC_KEY> \
  --head task/<beads_task_id> \
  --state merged --json number
```
And check: "if the JSON array is non-empty → PR was merged."

## Proposed Script: shared/check-pr-merged.sh

```bash
shared/check-pr-merged.sh <repo> <epic_key> <beads_task_id>
```

- Exits 0 if PR is merged, exits 1 if not
- Optionally prints the PR number to stdout (for traceability/logging)
- Handles the `--state merged --json number` flag, JSON parsing, and empty-array test once

## Call site changes in system-prompt.md

Replace all 3 `gh pr list` blocks with:
```bash
if shared/check-pr-merged.sh "<repo>" "<EPIC_KEY>" "<beads_task_id>"; then
```

## Test Infrastructure

- Tests live in `test/bats/*.bats` using the bats framework
- Tests mock external tools (e.g., `gh`, `bd`) by creating stub executables in a temp `$TMP_DIR` prepended to `$PATH`
- `shared/*.sh` is linted by `test/shellcheck.sh` via `make test`
- New script must pass shellcheck and have bats tests covering: merged case, not-merged case, and printing PR number

## File Structure

- New file: `shared/check-pr-merged.sh`
- New test file: `test/bats/check-pr-merged.bats`
- Modified: `majordomo/system-prompt.md` (3 call sites)

## Conventions from existing scripts

- Shell scripts use `#!/usr/bin/env bash` and `set -euo pipefail`
- Arguments via positional params ($1, $2, $3)
- Python3 inline for JSON parsing
- No comments beyond what's necessary
