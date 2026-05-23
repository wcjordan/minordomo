# Implementation Plan: MDOMO-69
# Remove docs/planning and docs/research for a task before merging to main

## Stage 1: Delete planning and research docs from feature branch in Majordomo Step 9

### Description
Modify `majordomo/system-prompt.md` Step 9 to delete `docs/planning/$EPIC_KEY-spec.md`
and the `docs/research/$EPIC_KEY/` directory from the feature branch before opening the
feature→base PR.  When humans squash-merge the PR, the planning and research artifacts
will not land on the base branch.

Insert a new sub-step **f2** after the existing "Extract GH Issue URL" step f and before
the "Read commit messages" step g.  (Placing cleanup *after* step f is critical — step f
can skip an Epic if no GH Issue URL is found, and we must not push cleanup commits to
branches we end up skipping.)

Sub-step f2 must:

1. Ensure `/tmp/spinoff-<EPIC_KEY>` is ready.  This directory is created by Step 6
   (Plan Approval Spinoff) but may not exist if that step ran in a previous container.
   This also fixes a latent bug where the existing step g (`git log`) would silently
   fail in a fresh container.
   - If the directory does not exist, clone it:
     ```bash
     gh repo clone wcjordan/<repo> /tmp/spinoff-<EPIC_KEY>
     ```
   - Fetch latest and check out the feature branch:
     ```bash
     git -C /tmp/spinoff-<EPIC_KEY> fetch origin
     git -C /tmp/spinoff-<EPIC_KEY> checkout feature/<EPIC_KEY>
     git -C /tmp/spinoff-<EPIC_KEY> pull --ff-only origin feature/<EPIC_KEY>
     ```

2. Delete the spec doc and research directory if they exist:
   ```bash
   git -C /tmp/spinoff-<EPIC_KEY> rm -f  --ignore-unmatch docs/planning/<EPIC_KEY>-spec.md
   git -C /tmp/spinoff-<EPIC_KEY> rm -rf --ignore-unmatch docs/research/<EPIC_KEY>/
   ```

3. If either deletion staged any changes
   (`git -C /tmp/spinoff-<EPIC_KEY> diff --cached --quiet` exits non-zero):
   ```bash
   git -C /tmp/spinoff-<EPIC_KEY> commit -m "chore: remove planning docs for <EPIC_KEY>"
   git -C /tmp/spinoff-<EPIC_KEY> push origin feature/<EPIC_KEY>
   ```
   If no changes were staged, skip the commit and continue.

4. On any error in this sub-step (clone, checkout, push): append a per-Epic error to
   `epic_errors`, increment `epics_skipped`, and continue to the next Epic (do not open
   a PR for a branch in an uncertain state).

Note: after this change, the spinoff directory is guaranteed to exist before step g
("Read commit messages"), which relied on its prior existence without ensuring it.

### Acceptance Criteria
- `majordomo/system-prompt.md` Step 9 contains new sub-step instructions to delete
  `docs/planning/<EPIC_KEY>-spec.md` and `docs/research/<EPIC_KEY>/` from the feature
  branch before opening the PR.
- The new instructions appear after step f (Extract GH Issue URL) and before step g
  (Read commit messages).
- Instructions ensure the spinoff directory exists (clone if absent), fetch, and check
  out the feature branch.
- Instructions handle the case where neither docs path exists (no empty commit made).
- Instructions treat cleanup errors as per-Epic errors (skip the Epic, do not abort).
- `make test` passes.

---

## Stage 2: Delete accumulated docs/planning and docs/research from main

### Description
Open a one-time cleanup PR that removes all `docs/planning/` and `docs/research/`
entries that have already accumulated on the main (base) branch from past Epic merges.

After Stage 1 is merged, future merges will no longer accumulate these files.  This
stage cleans up the backlog.

The worker should:
1. On the task branch (already checked out by the pipeline), delete the directories:
   ```bash
   git rm -rf docs/planning/ docs/research/
   ```
2. Commit:
   ```bash
   git commit -m "chore: remove accumulated planning and research docs"
   ```
3. Push and open a PR targeting the base branch (`$FEATURE_BRANCH`).

There is no risk of deleting in-progress artifacts: any Epic still in progress has its
spec doc on its own `feature/<EPIC_KEY>` branch, not on main.

### Acceptance Criteria
- `docs/planning/` and `docs/research/` are deleted from the base branch via a PR.
- The PR is merged to `$FEATURE_BRANCH` (the current epic's feature branch), which in
  turn will be merged to main.
- `make test` passes after the deletion (these directories contain only markdown docs,
  not code the tests depend on).
