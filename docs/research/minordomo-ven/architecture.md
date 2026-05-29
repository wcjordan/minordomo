# Research: No Longer Create/Check Jira Implementation Tasks

## Background

The minordomo pipeline currently creates Jira Implementation Tasks (child tasks under Jira Epics)
for each stage in an approved plan. These tasks are linked to beads Stage tasks via `external_ref`
(e.g. `"jira-MDOMO-45"`). The Jira task lifecycle is:
`Open → In Progress → In Review → Done`

The request is to stop creating these tasks entirely, and stop all lifecycle transitions for them.

## Files to Change

### `majordomo/system-prompt.md`

**Step 6 (Plan Approval Spinoff), sub-step h:**
- Creates one Jira Implementation Task per stage under the Epic
- Uses `mcp__atlassian__*` or Jira REST POST
- Captures `JIRA_IMPL_KEY_N` for use in step k

**Step 6, sub-step k:**
- Creates beads subtasks with `--external-ref "jira-${JIRA_IMPL_KEY_N}"`
- After removing Step h, this becomes just: create beads tasks without external-ref

**Step 4 (Sync PR Merge Status to Jira):**
- Identifies in_progress Stage tasks
- Sub-step b: extracts `jira_task_key` from `external_ref`
- Sub-step e: transitions Jira task to Done via `shared/jira-transition.sh`
- Still needs to close beads tasks when PR is merged
- Remove the Jira-specific parts; keep the beads close

**Step 8 (Launch Worker), sub-step 8:**
- Transitions Jira task to In Progress
- Sub-step comments say `(write — keep)` but this must now be removed
- Remove the `jira_task_key` extraction and Jira transition

### `minordomo-step/system-prompt.md`

**Step 1:**
- Currently extracts `jira_task_id` from `external_ref`
- Remove this extraction

**Step 7 (Transition Jira Task to In Review):**
- Calls `shared/jira-transition.sh "${jira_task_id}" "In Review"`
- Remove this entire step
- Update run log format to remove `jira_transition`

### `docs/WORKFLOWS.md`

- "Jira Ticket Hierarchy" section: remove Implementation Tasks from the hierarchy
- "Implementation Task" status flow section: remove entirely (no longer applies)
- "Stage (Implementation Task)" section: remove mention of `external_ref` Jira mirroring
- "Spec Documents" section: remove sentence about Jira tasks being created per stage
- "Prioritization" section: update references to Jira status (some are Jira epic-level, keep those)

### `CLAUDE.md` (top-level and `minordomo/CLAUDE.md`)

- "Task Identity & Ordering" section: remove "Every Jira Task and" from Implementation Tasks definition
- Remove "Stage ordering within an Epic: Use Jira rank" (no longer relevant for new tasks)
- Keep Jira Epic creation info (Epics are still created)

## What Stays Unchanged

- Jira Epic creation (Step 3) - still creates Epics for each GH Issue
- Jira Epic → "In Review" transition (Step 9n) - still transitions Epic when feature PR opened
- Jira Epic → "Done" transition (Step 10i) - still transitions Epic when feature PR merged
- `shared/jira-transition.sh` script - still needed for Epic transitions
- `shared/get-epic-key.sh` - still needed to get Jira Epic key for Epic transitions
- Worker needs-input flow - uses get-epic-key.sh for GH issue number (not Jira task key)

## Impact on In-Flight Tasks

Any existing beads Stage tasks that have `external_ref: "jira-XXXX"` will continue to have
that field - it just won't be acted upon. The corresponding Jira tasks won't be auto-transitioned,
but that's an acceptable migration edge case.

## Test Impact

- `make test` runs shellcheck, bats unit tests, and prompt validation
- No shell scripts change (only system-prompt.md and docs)
- Prompt validation only checks file paths and Jenkins job names - these won't break
- No bats test changes needed
