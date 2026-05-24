# Research: MDOMO-69 — Remove docs/planning and docs/research before merging to main

## Problem

`docs/planning/` and `docs/research/` accumulate indefinitely on the main branch.
As of 2026-05-23 the repo has 13 spec files and 13 research directories on main that
will never be needed again once the Epic they supported is complete.

## Where These Files Come From

1. **Planning Agent** creates both directories on `task/$JIRA_TASK_ID`:
   - `docs/planning/$EPIC_KEY-spec.md` — the multi-stage implementation plan
   - `docs/research/$EPIC_KEY/*.md` — research notes (may span re-runs)
2. The planning PR merges those files into `feature/$EPIC_KEY`.
3. Workers read `docs/planning/$EPIC_KEY-spec.md` from the feature branch during
   implementation; they may also update it if the plan changes mid-execution.
4. **Majordomo Step 9** opens the `feature/$EPIC_KEY → base` PR (squash merge).
   Currently no cleanup happens — the files land on main unchanged.

## Where to Add Cleanup

**Step 9 of Majordomo** (`majordomo/system-prompt.md`, line ~340) is the right place:

- Step 9 runs only when *all* Implementation Tasks for an Epic are `Done`.
- At that point no worker will ever need the spec doc again.
- The step already uses a `/tmp/spinoff-<EPIC_KEY>` directory for git operations
  (reading commit logs at line ~376), so git access to the feature branch is
  already required.

**Approach:** Before opening the PR, delete the planning and research docs from the
feature branch, commit, and push. The subsequent squash merge to main will then
not include those files.

## Spinoff Directory Lifecycle

`/tmp/spinoff-<EPIC_KEY>` is created by Step 6 (Plan Approval Spinoff) when it
processes an approved planning task. Step 9 reuses this directory with
`git -C /tmp/spinoff-<EPIC_KEY>`. Because Majordomo runs in an ephemeral Jenkins
container, this directory may *not* exist when Step 9 runs (Step 6 may have last
run in a different container). The cleanup sub-step should:

1. Check if `/tmp/spinoff-<EPIC_KEY>` exists.
2. If not, clone: `gh repo clone wcjordan/<repo> /tmp/spinoff-<EPIC_KEY>`.
3. Fetch and checkout the feature branch.

This also fixes a latent bug where step g (read commit messages) would fail if the
spinoff directory was absent.

## Files to Delete

| Path | Notes |
|---|---|
| `docs/planning/$EPIC_KEY-spec.md` | Always present if a spec was written |
| `docs/research/$EPIC_KEY/` | Present if planning agent saved research notes |

Both should be deleted only if they exist (older epics may not have them).

## Edge Cases

- **Neither file exists**: skip commit, continue to PR open step.
- **Spec exists but research dir does not** (or vice-versa): delete only what exists.
- **Spinoff dir absent**: clone before operating.
- **Push fails**: treat as a per-Epic error (append to `epic_errors`, skip this Epic).

## Key File

`majordomo/system-prompt.md` — the only file that needs to change for Stage 1.
