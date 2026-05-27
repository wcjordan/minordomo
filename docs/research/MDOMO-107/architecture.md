# Research: Switch EPIC_KEY to Story Bead Name (MDOMO-107)

## Current Behavior

`shared/get-epic-key.sh <beads_task_id> <repo>` outputs:
- Line 1: Jira Epic key (e.g. `MDOMO-107`) — extracted from "Jira Epic: XXXX" comment in the linked GH issue
- Line 2: GH issue number (e.g. `169`)

Called by:
- `shared/setup-workspace.sh` — reads line 1 as EPIC_KEY, used for feature branch name and file paths
- `majordomo/system-prompt.md` — Helpers 2/3, Step 4 (Stage/Plan PR checks), Step 6.b (spinoff), Step 9.f (epic PR opening)
- `minordomo-step/system-prompt.md` — Needs Input flow (line 1 discarded with `_EPIC_KEY`, line 2 used)

## Desired Behavior

EPIC_KEY should be the ID of the "Story" bead (e.g. `minordomo-epf`) rather than the Jira Epic key.

Bead hierarchy:
- Story bead: `minordomo-epf` (title starts with "Story:")
  - Plan bead: `minordomo-epf.1` (child, title starts with "Plan:")
  - Stage beads: `minordomo-epf.2`, etc. (children, title starts with "Stage")

`get-epic-key.sh` can be called with:
- A Plan/Stage bead — walk to parent to find Story bead
- A Story bead directly (as in Majordomo Step 9) — it IS the Story bead

## Impact Analysis

### Files that change:

1. **`shared/get-epic-key.sh`** (core change)
   - New output: line 1 = Story bead ID, line 2 = GH issue number, line 3 = Jira Epic key
   - Walk parent chain: if title starts "Story:", use self; else use parent (which must start "Story:")
   - GH issue URL comes from Story bead's description field
   - Jira Epic key still read from "Jira Epic:" comment in GH issue (for transition callers)

2. **`test/bats/get-epic-key.bats`**
   - Mock `bd` must return parent bead with "Story:" title prefix
   - Line 1 check changes from Jira key to Story bead ID
   - New line 3 check for Jira Epic key

3. **`shared/setup-workspace.sh`**
   - Read all 3 lines from `get-epic-key.sh`
   - Add migration fallback: if `feature/<story-bead-id>` doesn't exist on remote but
     `feature/<jira-epic-key>` does, rename the old branch to the new name
   - This handles in-flight epics created before this change deployed

4. **`test/dry-run.sh`**
   - Mock `bd` parent bead title: "Plan: Test feature" → "Story: Test feature"
   - EPIC_KEY assertion: `MDOMO-1` → `minordomo-100` (the story bead ID from mock)

5. **`majordomo/system-prompt.md`**
   - Helper 2 (Step 4, line ~110): update to capture 3 lines, expose `JIRA_EPIC_KEY`
   - Step 6.b (~line 238): update comment to reflect new derivation
   - Step 8.b (~line 311): update comment
   - Step 9.f (~line 380): add `JIRA_EPIC_KEY` capture as 3rd line
   - Step 9.n (~line 457): change `"${EPIC_KEY}"` → `"${JIRA_EPIC_KEY}"` in jira-transition call

6. **`minordomo-step/system-prompt.md`**
   - Needs Input flow (~line 122): add `_JIRA_EPIC_KEY` to capture 3 lines cleanly

7. **`docs/WORKFLOWS.md`**
   - Example branch `feature/PROJ-42` → `feature/story-bead-id` (cosmetic)

8. **`docs/agent-workflow-spec.md`** and **`docs/FUTURE_WORK.md`**
   - References to `docs/planning/<EPIC_KEY>-spec.md` remain accurate — EPIC_KEY just changes format

## Migration Concern

**Problem**: Feature branches already created before this change use Jira key naming (e.g. `feature/MDOMO-107`). After deployment, `get-epic-key.sh` returns `minordomo-epf` → worker looks for `feature/minordomo-epf` (doesn't exist) → FAILS.

**Solution**: Migration fallback in `setup-workspace.sh`:
- After deriving new EPIC_KEY and FEATURE_BRANCH, check if FEATURE_BRANCH exists on remote
- If not: read JIRA_EPIC_KEY (line 3), check if `feature/<jira-epic-key>` exists
- If old branch found: rename it (push new name, delete old name) and update FEATURE_BRANCH
- This runs automatically on the first planning or worker run after deployment

**Branch rename via git:**
```bash
git checkout -b "${FEATURE_BRANCH}" "origin/${OLD_FEATURE_BRANCH}"
git push -u origin "${FEATURE_BRANCH}"
git push origin --delete "${OLD_FEATURE_BRANCH}"
```

Open PRs targeting the old branch name would become orphaned, but in practice, any open
PRs are stage-to-feature PRs which must be merged before the epic PR is opened. If any
are still open when the rename happens, their base must be updated manually.

## Stage Breakdown

- Stage 1: Update `get-epic-key.sh` + `test/bats/get-epic-key.bats`
- Stage 2: Update `setup-workspace.sh` (3-line read + migration fallback) + `test/dry-run.sh`
- Stage 3: Update `majordomo/system-prompt.md`
- Stage 4: Update `minordomo-step/system-prompt.md` + docs
