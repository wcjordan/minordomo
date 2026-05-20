# MDOMO-58 Implementation Plan: Planning task should be a bead under the story

## Background

Currently the `Plan:` beads task is the top-level parent, and all Stage implementation tasks are children of it. When the Plan task is closed (after the plan PR merges), Stage tasks are orphaned under a closed parent — and `bd ready` may not surface them correctly.

The fix: introduce a `Story:` bead as the top-level Epic equivalent. Both the `Plan:` task and all `Stage N:` tasks become children of the Story. The Story stays open until all implementation work completes.

---

## Stage 1: Create Story bead on ingestion and nest Plan bead under it

### Description

Modify Step 3 of `majordomo/system-prompt.md` so that when a new GitHub Issue is ingested, the pipeline creates a `Story:` bead first (as the top-level task), then creates the `Plan:` bead as a child of it.

Currently (line ~66):
```bash
bd create "Plan: <issue title>" --priority <priority> --description "GH Issue: <issue url>"
```

Replace with:
```bash
BEADS_STORY_ID=$(bd create "Story: <issue title>" --priority <priority> --description "GH Issue: <issue url>" --json | jq -r '.id')
if [ -z "$BEADS_STORY_ID" ]; then
  # log per-issue error: beads_story_task_creation_failed; continue
fi
bd create "Plan: <issue title>" --parent "$BEADS_STORY_ID" --priority <priority> --description "GH Issue: <issue url>"
```

The `beads-ingested` label and error-handling semantics remain the same — a failure in either `bd create` call logs a per-issue error and continues without aborting other issues.

### Acceptance Criteria
- When Majordomo ingests a new GitHub Issue, it creates a `Story: <title>` beads task with no parent
- A `Plan: <title>` beads task is created as a child of the Story task
- The `beads-ingested` label is still applied to the GH Issue on success
- A `bd create` failure for either bead logs a per-issue error and does not abort processing of other issues
- Existing beads-creation error handling in Step 3 is preserved

---

## Stage 2: Nest Stage beads under Story in Step 6, and update Story completion check in Step 9

### Description

Two related changes to `majordomo/system-prompt.md`:

**Step 6 (Plan Approval Spinoff):** Currently finds the Plan bead and parents Stage beads under it. Change it to find the Story bead instead and parent Stage beads under the Story.

Currently (lines ~185–192):
```bash
BEADS_PLAN_ID=$(bd list --json | jq -r '[.[] | select(.title == "Plan: <issue title>")] | first | .id // empty')
# ...
BEADS_STAGE_N_ID=$(bd create "Stage N: <title>" --parent "$BEADS_PLAN_ID" --json | jq -r '.id')
```

Replace with:
```bash
BEADS_STORY_ID=$(bd list --json | jq -r '[.[] | select(.title == "Story: <issue title>")] | first | .id // empty')
# ...
BEADS_STAGE_N_ID=$(bd create "Stage N: <title>" --parent "$BEADS_STORY_ID" --json | jq -r '.id')
```

Update the not-found error log label from `"beads_plan_task_not_found"` to `"beads_story_task_not_found"`.

**Step 9 (Story Completion check):** Currently finds the Plan bead to check whether its children are all done. Change it to find the Story bead instead.

Currently (lines ~319–322):
```bash
BEADS_PLAN_ID=$(bd list --json | jq -r --arg title "Plan: <epic_summary>" \
  '[.[] | select(.title == $title)] | first | .id // empty')
if [ -n "$BEADS_PLAN_ID" ]; then
  bd list --parent "$BEADS_PLAN_ID" --json | jq 'all(.status == "done")'
```

Replace with:
```bash
BEADS_STORY_ID=$(bd list --json | jq -r --arg title "Story: <epic_summary>" \
  '[.[] | select(.title == $title)] | first | .id // empty')
if [ -n "$BEADS_STORY_ID" ]; then
  bd list --parent "$BEADS_STORY_ID" --json | jq 'all(.status == "done")'
```

### Acceptance Criteria
- After plan approval spinoff, Stage beads are children of the `Story:` bead (not the `Plan:` bead)
- The `Plan:` bead remains a child of the `Story:` bead and is not affected by Step 6
- The blocking chain between consecutive Stage beads is unchanged
- In Step 9, the completion check inspects children of `Story:` rather than children of `Plan:`
- If no matching Story bead is found in Step 6 or Step 9, the existing error-handling semantics are preserved (log error, do not abort)
- Running `make test` passes with no new failures
