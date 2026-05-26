# Research: Extract beads→epic key lookup to shared/get-epic-key.sh

## Problem

Deriving `EPIC_KEY` from a beads task requires the same 4-step chain in multiple places:

1. `bd show <parent_id> --json` → extract GH Issue URL from `.description`
2. `grep -Eo 'https://github.com/...'` → isolate the URL
3. `gh issue view <number> --repo wcjordan/<repo> --json comments` → fetch comments
4. Python regex `r'Jira Epic: ([A-Z]+-[0-9]+)'` → extract the key

## Current Occurrences

### `majordomo/system-prompt.md`

- **Helper 2** (Step 4 prologue, lines ~112–127): Full inline bash block; referenced by Steps 4c, 5c.
- **Step 6 Plan Approval Spinoff** (lines ~258–259): References "Step 4 helper" — uses the inline block above.
- **Step 8 Launch Worker** (line ~335): Also references "Step 4 helper".
- **Step 9 Open Feature PRs** (lines ~405–418): Inline duplicate of the same pattern (starts from story description directly, not via `bd show`).

### `minordomo-step/system-prompt.md`

- **Needs Input Flow** (lines ~135–139): Only derives `GH_ISSUE_NUMBER` (not EPIC_KEY) via `bd show` parent chain + URL extraction. Does not do the `gh issue view` step.

### `shared/setup-workspace.sh`

- **Lines 51–79**: Same logic embedded inline, with a slight extension: checks both the task's own description AND the parent's description if the first is empty. Exports `EPIC_KEY` and uses `GH_ISSUE_NUMBER` directly.
- Runs in cloned-repo context; beads data available after `bd bootstrap && bd dolt pull`.

## Proposed Script: `shared/get-epic-key.sh`

**Interface:**
```bash
shared/get-epic-key.sh <beads_task_id> <repo>
```

**Output** (stdout, two lines):
```
MDOMO-86
142
```
Line 1: EPIC_KEY, Line 2: GH_ISSUE_NUMBER.

**Logic:**
1. `bd show <beads_task_id> --json` → extract description
2. Try to find GH Issue URL in description; if not found, try parent's description
3. Extract issue number from URL
4. `gh issue view <number> --repo wcjordan/<repo> --json comments`
5. Find `Jira Epic: KEY` comment via regex
6. Print EPIC_KEY and GH_ISSUE_NUMBER; exit 0
7. Exit 1 with stderr message if any step fails

**Caller pattern (updated majordomo):**
```bash
EPIC_OUTPUT=$(shared/get-epic-key.sh "$PARENT_ID" "$REPO")
EPIC_KEY=$(echo "$EPIC_OUTPUT" | head -1)
GH_ISSUE_NUMBER=$(echo "$EPIC_OUTPUT" | tail -1)
```

## Out of Scope

Refactoring `shared/setup-workspace.sh` to call `get-epic-key.sh` is not included. `setup-workspace.sh` runs inside the cloned repo and has slightly different context (it already handles multi-level fallback). This can be done as a follow-up.

## Test Considerations

- `make test` runs `shellcheck shared/*.sh` — the new script must pass shellcheck.
- `test/validate-prompts.py` checks that backtick-quoted paths in system prompts exist on disk — after the refactor, `shared/get-epic-key.sh` must exist for the path reference in system prompts to pass.
