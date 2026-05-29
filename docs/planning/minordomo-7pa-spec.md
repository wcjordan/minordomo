# Implementation Plan: Remove migration fallback from setup-workspace.sh

**Epic:** minordomo-7pa  
**Jira Epic:** MDOMO-122  
**GH Issue:** https://github.com/wcjordan/minordomo/issues/185

---

## Stage 1: Remove migration fallback and its test

### Description

Remove the temporary migration shim added in PR #183 from `shared/setup-workspace.sh`.
The shim falls back from `feature/<beads-id>` to `feature/<jira-epic-key>` branch lookup
when the beads-ID-named branch doesn't exist on the remote. The issue author confirms all
active feature branches have migrated or closed, so the shim can be safely deleted.

Three concrete edits:

1. **`shared/setup-workspace.sh`** — delete the migration fallback block (currently
   lines 55–66, the comment and the `if ! git ls-remote ... fi` block) and rename
   the `JIRA_EPIC_KEY` capture in the `read` statement at line 50 to `_JIRA_EPIC_KEY`
   (following the existing `_GH_ISSUE_NUMBER` convention for discarded outputs).

2. **`test/bats/setup-workspace.bats`** — remove the test titled
   `"migration: renames old Jira-key-named feature branch to new beads-id branch"`.
   Leave the `gh "issue view"` mock case in place — `get-epic-key.sh` still calls it
   for the Jira Epic key that Majordomo uses in Jira transitions.

Do NOT modify `shared/get-epic-key.sh`: `JIRA_EPIC_KEY` is still emitted on line 3
and consumed by `majordomo/system-prompt.md` (`shared/jira-transition.sh "${JIRA_EPIC_KEY}"`).

### Acceptance Criteria

- Migration block (lines 55–66 of `shared/setup-workspace.sh`) is removed
- The `read` statement on line 50 uses `_JIRA_EPIC_KEY` (not `JIRA_EPIC_KEY`) to discard the third output
- `test/bats/setup-workspace.bats` no longer contains the migration test
- `shared/get-epic-key.sh` is unchanged
- `make test` passes (shellcheck, bats, prompt validation all green)
