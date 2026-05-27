# Implementation Plan: Switch EPIC_KEY to Story Bead Name (MDOMO-107)

## Background

Currently `shared/get-epic-key.sh` returns the Jira Epic key (e.g. `MDOMO-107`) as line 1 (EPIC_KEY), which is used for feature branch names (`feature/MDOMO-107`), spec doc paths, and research doc paths. The goal is to use the Story bead's ID (e.g. `minordomo-epf`) instead, making the EPIC_KEY independent of Jira.

See `docs/research/MDOMO-107/architecture.md` for full impact analysis.

---

## Stage 1: Update get-epic-key.sh to return Story bead ID as EPIC_KEY

### Description

Change `shared/get-epic-key.sh` to derive EPIC_KEY from the Story bead's ID rather than the Jira Epic key.

**New output contract (3 lines):**
- Line 1: Story bead ID (new EPIC_KEY, e.g. `minordomo-epf`)
- Line 2: GH issue number (unchanged)
- Line 3: Jira Epic key (e.g. `MDOMO-107`, for callers that need it for Jira transitions)

**Story bead lookup logic:**
- If the task's own title starts with `"Story:"`, it is the Story bead — use its ID
- Otherwise, look at the parent bead. If the parent's title starts with `"Story:"`, use its ID
- If neither condition is satisfied, exit 1 with a descriptive error
- The GH issue URL is read from the Story bead's description field (not the child's)

**Update `test/bats/get-epic-key.bats`:**
- Change mock `bd` responses so the parent bead has a title starting with `"Story:"`
- Change line 1 assertions: expect the Story bead ID (e.g. `"test-1"`) instead of the Jira key
- Add assertions on line 3: expect the Jira Epic key (e.g. `"MDOMO-10"`)
- Add a new test: Story bead is the task itself (title starts "Story:"), no parent lookup needed
- Add a new test: happy path where `get-epic-key.sh` is called with the Story bead directly

### Acceptance Criteria
- `shared/get-epic-key.sh` outputs 3 lines: Story bead ID, GH issue number, Jira Epic key
- When called with a Plan/Stage bead, it walks to the parent to find the Story bead
- When called with a Story bead directly, it returns that bead's ID on line 1
- When neither task nor parent has a "Story:" title, it exits 1 with an error message
- All `test/bats/get-epic-key.bats` tests pass under `make test`

---

## Stage 2: Update setup-workspace.sh with 3-line read and migration fallback

### Description

Update `shared/setup-workspace.sh` to read all 3 lines from `get-epic-key.sh` and add a migration fallback to handle feature branches created before this change was deployed.

**3-line read:**
Replace:
```bash
EPIC_KEY=$("$(dirname "${BASH_SOURCE[0]}")/get-epic-key.sh" "${BEADS_TASK_ID}" "${REPO}" | head -1)
```
With:
```bash
{ read -r EPIC_KEY; read -r _GH_ISSUE_NUMBER; read -r JIRA_EPIC_KEY; } \
    < <("$(dirname "${BASH_SOURCE[0]}")/get-epic-key.sh" "${BEADS_TASK_ID}" "${REPO}")
```

**Migration fallback (insert after deriving FEATURE_BRANCH):**
After deriving `FEATURE_BRANCH="feature/${EPIC_KEY}"`, check whether the new-style branch exists on the remote. If not, but the old Jira-key-named branch (`feature/<JIRA_EPIC_KEY>`) exists, rename it:
```bash
if ! git ls-remote --exit-code origin "${FEATURE_BRANCH}" > /dev/null 2>&1; then
    OLD_FEATURE_BRANCH="feature/${JIRA_EPIC_KEY}"
    if git ls-remote --exit-code origin "${OLD_FEATURE_BRANCH}" > /dev/null 2>&1; then
        echo "Migrating feature branch: ${OLD_FEATURE_BRANCH} → ${FEATURE_BRANCH}"
        git fetch origin "${OLD_FEATURE_BRANCH}"
        git checkout -b "${FEATURE_BRANCH#refs/heads/}" "origin/${OLD_FEATURE_BRANCH}"
        git push -u origin "${FEATURE_BRANCH}"
        git push origin --delete "${OLD_FEATURE_BRANCH}"
    fi
fi
```
Note: this applies in both planning and worker modes.

**Update `test/dry-run.sh`:**
- Change mock `bd` parent bead title from `"Plan: Test feature"` to `"Story: Test feature"`
- Change the `EPIC_KEY` assertion from `"MDOMO-1"` to `"minordomo-100"` (the Story bead ID from the mock)

### Acceptance Criteria
- `shared/setup-workspace.sh` reads all 3 lines from `get-epic-key.sh` (EPIC_KEY, ignored GH number, JIRA_EPIC_KEY)
- When the new-style feature branch doesn't exist but the old Jira-key-named branch does, the old branch is renamed to the new name
- `test/dry-run.sh` passes end-to-end after mock updates
- `make test` passes

---

## Stage 3: Update Majordomo system prompt

### Description

Update `majordomo/system-prompt.md` to use the new 3-line `get-epic-key.sh` output and to use `JIRA_EPIC_KEY` (not `EPIC_KEY`) when calling `jira-transition.sh` for the Jira Epic.

**Changes:**

1. **Helper 2 description** (Step 4, "Helper: derive EPIC_KEY and GH_ISSUE_NUMBER"):
   - Update description to say "prints Story bead ID (EPIC_KEY) on line 1, GH_ISSUE_NUMBER on line 2, and Jira Epic key on line 3"
   - Update the bash snippet to capture 3 lines:
     ```bash
     { read -r EPIC_KEY; read -r GH_ISSUE_NUMBER; read -r JIRA_EPIC_KEY; } < <(shared/get-epic-key.sh "<beads_task_id>" "<repo>")
     ```

2. **Step 6.b** (Plan Approval Spinoff — "Derive EPIC_KEY using the Step 4 helper"):
   - Update the inline comment to say "parent Story bead → Story bead ID" instead of "Jira Epic: comment"

3. **Step 8.b** (Launch Worker — "Derive EPIC_KEY and GH Issue number using the Step 4 helper"):
   - Update the comment similarly

4. **Step 9.f** (Open Feature PRs — "Derive EPIC_KEY and GH Issue"):
   - Update capture from 2 to 3 lines:
     ```bash
     { read -r EPIC_KEY; read -r GH_ISSUE_NUMBER; read -r JIRA_EPIC_KEY; } < <(shared/get-epic-key.sh "<story_bead_id>" "<repo>")
     ```

5. **Step 9.n** (Transition Epic to In Review):
   - Change `shared/jira-transition.sh "${EPIC_KEY}" "In Review"` to `shared/jira-transition.sh "${JIRA_EPIC_KEY}" "In Review"`

### Acceptance Criteria
- Helper 2 in majordomo system prompt captures 3 lines from `get-epic-key.sh` and exposes `JIRA_EPIC_KEY`
- Step 9.n calls `jira-transition.sh "${JIRA_EPIC_KEY}"` instead of `"${EPIC_KEY}"`
- Step 6.b and Step 8.b comments reference "Story bead ID" rather than "Jira Epic: comment"
- `make test` passes (prompt validation)

---

## Stage 4: Update worker system prompt and docs

### Description

Update `minordomo-step/system-prompt.md` and documentation files to reflect the new EPIC_KEY format.

**`minordomo-step/system-prompt.md`** — Needs Input Flow, Step 1:
- Add `_JIRA_EPIC_KEY` to drain the 3rd line from `get-epic-key.sh`:
  ```bash
  { read -r _EPIC_KEY; read -r GH_ISSUE_NUMBER; read -r _JIRA_EPIC_KEY; } < <(shared/get-epic-key.sh "${BEADS_TASK_ID}" "$REPO")
  ```
- Update the example `spec_doc_path` in the run log example from `"docs/planning/MDOMO-36-spec.md"` to `"docs/planning/minordomo-xxx-spec.md"` to reflect the new naming

**`docs/WORKFLOWS.md`**:
- Update the example directory tree showing `feature/PROJ-42` to use `feature/story-bead-id` format

**`docs/agent-workflow-spec.md`**:
- No code changes needed; the file mentions `docs/planning/<EPIC_KEY>-spec.md` which remains accurate regardless of EPIC_KEY format

**`docs/FUTURE_WORK.md`**:
- No changes needed; reference to `docs/planning/<EPIC_KEY>-spec.md` is a template, not an example

### Acceptance Criteria
- `minordomo-step/system-prompt.md` Needs Input Flow captures 3 lines from `get-epic-key.sh`
- `docs/WORKFLOWS.md` example shows beads-style branch name (not Jira key style)
- `make test` passes
