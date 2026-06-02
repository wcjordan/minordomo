# Research: minordomo-c8s

GH Issue #290: "A PR to main should not be opened until the PR for the final stage has not yet been merged"

## Issue Analysis

The issue title has a double negative ("has not yet been merged") making the intent ambiguous. Body is empty. Best interpretation: "a feature→main PR should not be opened while the final stage PR (task→feature) is still unmerged."

## Observed Evidence

PR history for minordomo-17r (Discord notifications epic):
- #279: task/minordomo-17r.2 → feature/minordomo-17r (Stage 1) ✓
- #282: task/minordomo-17r.3 → feature/minordomo-17r (Stage 2) ✓
- #284: task/minordomo-17r.4 → **main** (Stage 3 - wrong base!)
- #285: feature/minordomo-17r → main (Feature PR — opened despite Stage 3 anomaly)

## How the Current Pipeline Works

1. **Worker** opens a PR from `task/<beads_task_id>` to `$FEATURE_BRANCH`
2. **Majordomo Step 4** (`Sync PR Merge Status`): for each `in_progress` Stage task, calls `check-pr-merged.sh` which looks for a `task→feature` PR that is merged. If found → closes the beads task.
3. **Majordomo Step 9** (`Open Feature → Main PRs for Completed Stories`): if all Stage tasks are `closed`, opens the feature→main PR.

## Root Cause Hypotheses

The Step 9 check (all Stage tasks closed) should prevent premature PR opening IF beads task status is reliable. But several scenarios could break this:

1. **Worker opened PR to wrong base**: PR #284 went `task/minordomo-17r.4 → main` (not `→ feature/minordomo-17r`). `check-pr-merged.sh` looks for `task→feature` PRs only, so it would never find this merged. Stage 3 task would stay `in_progress`. But then Step 9 should skip... unless the task was manually closed.

2. **FEATURE_BRANCH env var was `main`**: The worker environment may have had `FEATURE_BRANCH=main` due to a bug in `setup-workspace.sh`. In this case, the PR base would be `main`, and also the beads task close_reason would reference `feature/main` rather than `feature/minordomo-17r`. This seems unlikely.

3. **Beads task manually closed**: If someone ran `bd close minordomo-17r.4` directly after PR #284 was merged to main, the beads state would show all stages closed, and Step 9 would open the feature→main PR.

4. **Stage 3 added mid-flight without beads task**: If Stage 3 was added to the spec but never got a beads task, Step 9 would only check the existing beads tasks (Stages 1 and 2) and see them both closed — then open the main PR even though Stage 3's code wasn't done.

## Key Unresolved Questions

1. **Which scenario actually occurred?** We need the Majordomo run log for the run that opened PR #285 to know why Step 9 decided to open it.

2. **Was there a beads task for Stage 3 (minordomo-17r.4)?** If yes: what was its status when #285 was opened? If no: how did the spec have Stage 3 without a beads task?

3. **What is the desired fix scope?** Options:
   - Fix Majordomo Step 9 to verify via `gh pr list` that all task→feature PRs are merged (not just beads state)
   - Fix the worker to never open PRs to the wrong base
   - Both

## Relevant Files

- `majordomo/system-prompt.md` — Step 9 (Open Feature → Main PRs)
- `shared/check-pr-merged.sh` — checks if task→feature PR is merged (exit 0 = merged)
- `shared/check-epic-pr-merged.sh` — checks if feature→main PR is merged
- `shared/list-story-beads.sh` — lists open Story beads
- `minordomo-step/system-prompt.md` — worker Step 6 opens PR to `$FEATURE_BRANCH`
- `test/bats/check-pr-merged.bats` — reference test pattern for new scripts
