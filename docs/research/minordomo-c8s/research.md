# Research: minordomo-c8s

GH Issue #290: "A PR to main should not be opened until the PR for the final stage has not yet been merged"

## Issue Analysis

The issue title has a double negative ("has not yet been merged") making the intent ambiguous. Body is empty.
Confirmed interpretation (owner comment 2026-06-02): "a feature→main PR should not be opened while any
final stage PR (task→feature) is still unmerged / open."

## Owner Clarification (GH #290 comment)

The owner observed: after the step worker is launched for the final stage, there are **two** open PRs:
1. The final stage PR (`task/epic.N → feature/epic`) — just opened by the worker
2. The feature→main PR (`feature/epic → main`) — opened prematurely; includes prior stages but not stage N

Owner chose **Option A** as the fix: add a safety check in Majordomo Step 9 that verifies (via `gh pr list`)
no open `task/` PRs are targeting the feature branch before opening the feature→main PR.
Owner also noted the beads check could be strengthened ("does it check in_progress beads?").

## Verified: `bd list --all` Includes in_progress

Empirically verified: `bd list --all --json` returns tasks with status `in_progress` (confirmed by checking
current in_progress tasks like `minordomo-c8s.1` appear in the output). So `--all` = open + in_progress + closed.

The existing Step 9e check ("if any Stage task status is not closed") SHOULD catch in_progress tasks, since
`--all` includes them. However, this is not obvious from the `--all` description alone ("Show all issues
including closed"), so the instruction should be made explicit.

## Root Cause Assessment

The exact root cause of the observed double-PR situation is unclear, but the fix is clear:
- **Primary fix**: Use explicit `--status=open,in_progress,closed` in Step 9c (unambiguous to the AI executor)
- **Defense in depth**: Add GH PR safety check (owner's Option A) to catch beads-inconsistency edge cases

## How the Current Pipeline Works

1. **Worker** opens a PR from `task/<beads_task_id>` to `$FEATURE_BRANCH`
2. **Majordomo Step 4** (`Sync PR Merge Status`): for each `in_progress` Stage task, calls `check-pr-merged.sh`
   which looks for a `task→feature` merged PR. If found → closes the beads task.
3. **Majordomo Step 9** (`Open Feature → Main PRs for Completed Stories`): if all Stage tasks are `closed`,
   opens the feature→main PR.

## Relevant Files

- `majordomo/system-prompt.md` — Step 9 (Open Feature → Main PRs), Step 9c specifically
- `shared/check-pr-merged.sh` — checks if task→feature PR is merged (exit 0 = merged)
- `shared/check-epic-pr-merged.sh` — checks if feature→main PR is merged
- `shared/list-story-beads.sh` — lists open Story beads
- `test/bats/check-pr-merged.bats` — reference test pattern for new shared scripts
