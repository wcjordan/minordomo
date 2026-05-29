# Research: Remove migration fallback from setup-workspace.sh

## GH Issue
https://github.com/wcjordan/minordomo/issues/185

## Jira Epic
MDOMO-122

## What the migration fallback does

`shared/setup-workspace.sh` lines 55–66 contain a shim added in PR #183. When the
new-style feature branch `feature/<beads-id>` doesn't exist on the remote but an
old Jira-key-named branch `feature/<JIRA_EPIC_KEY>` does, it:
1. Fetches the old branch
2. Creates a new branch with the beads-id name at the same commit
3. Pushes the new branch
4. Deletes the old branch

The fallback was always temporary: it exists to smooth migration for repos that
hadn't yet moved to beads-ID-based branch naming.

## Dependency: JIRA_EPIC_KEY

`JIRA_EPIC_KEY` comes from `shared/get-epic-key.sh` (line 3 of its output). It is
still actively used by `majordomo/system-prompt.md` (line 440):
  `shared/jira-transition.sh "${JIRA_EPIC_KEY}" "In Review"`

**Do NOT remove JIRA_EPIC_KEY from get-epic-key.sh.** Only setup-workspace.sh's
capture of it needs to become a throwaway (`_JIRA_EPIC_KEY`).

## Files to change

| File | Change |
|------|--------|
| `shared/setup-workspace.sh` | Remove migration fallback block (lines 55–66); rename `JIRA_EPIC_KEY` capture to `_JIRA_EPIC_KEY` |
| `test/bats/setup-workspace.bats` | Remove `migration: renames old Jira-key-named feature branch` test |

## Files to leave alone

| File | Reason |
|------|--------|
| `shared/get-epic-key.sh` | JIRA_EPIC_KEY still emitted on line 3; consumed by majordomo |
| `test/bats/setup-workspace.bats` mock | `gh "issue view"` mock stays; get-epic-key.sh still calls it |
| Docs | No migration-specific doc content found to clean up |
