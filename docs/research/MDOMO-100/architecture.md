# Research: Extract needs-input flow (MDOMO-100)

## Problem

The "needs-input" flow — apply label, post comment, reset beads task — appears verbatim in two system prompts:

1. **Planning agent** (`minordomo-plan/system-prompt.md`, Questions Path, ~line 80):
   ```bash
   gh issue edit <gh_issue_number> --repo wcjordan/<repo> --add-label needs-input
   gh issue comment <gh_issue_number> --repo wcjordan/<repo> --body "<numbered question list>"
   shared/beads-write.sh update "${BEADS_TASK_ID}" --status open
   ```

2. **Worker agent** (`minordomo-step/system-prompt.md`, Needs Input Flow, ~line 125):
   ```bash
   gh issue edit <issue-number> --repo wcjordan/<repo> --add-label needs-input
   gh issue comment <issue-number> --repo wcjordan/<repo> --body "<explanation>"
   shared/beads-write.sh update "${BEADS_TASK_ID}" --status open
   ```

## Proposed Script Interface

```bash
shared/apply-needs-input.sh <repo> <issue_number> <beads_task_id> <comment_body>
```

Internally:
1. `gh issue edit <issue_number> --repo wcjordan/<repo> --add-label needs-input`
2. `gh issue comment <issue_number> --repo wcjordan/<repo> --body "<comment_body>"`
3. `$(dirname "${BASH_SOURCE[0]}")/beads-write.sh update <beads_task_id> --status open`

Exits non-zero logging which step failed if any step fails.

## Existing Script Patterns

All shared scripts follow this structure:
- `#!/usr/bin/env bash` + `set -euo pipefail`
- Usage guard on each positional arg (`:?` or explicit check)
- Per-step error handling with stderr messages
- Located in `shared/`

The `beads-write.sh` wrapper handles dolt pull/push around any `bd` write operation. The `apply-needs-input.sh` script should call `$(dirname "${BASH_SOURCE[0]}")/beads-write.sh` so it works from any working directory.

## Test Pattern

All bats tests in `test/bats/`:
- `setup()` sets `REPO_ROOT`, creates a `TMP_DIR` or `BATS_TEST_TMPDIR/mocks`, prepends to PATH
- Mock `gh` and `bd` executables in that directory
- Test happy path and each failure mode

## Impact on System Prompts

After the script exists:
- Planning agent: Questions Path step 1 becomes:
  `shared/apply-needs-input.sh wcjordan/minordomo "$gh_issue_number" "$BEADS_TASK_ID" "<questions>"`
- Worker agent: Needs Input Flow steps 2–4 become:
  `shared/apply-needs-input.sh "$REPO" "$GH_ISSUE_NUMBER" "$BEADS_TASK_ID" "<explanation>"`

The worker's step 1 (finding GH issue number) remains unchanged — it uses `shared/get-epic-key.sh`.
