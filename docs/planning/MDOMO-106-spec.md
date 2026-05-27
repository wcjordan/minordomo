# MDOMO-106 Implementation Plan: No longer create or check for "Plan" tasks in Jira

Now that beads is used for all Plan task tracking, remove all Jira interactions specific to "Plan:" tasks. Three stages: Majordomo orchestrator changes, planning agent changes, then documentation updates.

---

## Stage 1: Remove Jira Plan task interactions from Majordomo

### Description

Edit `majordomo/system-prompt.md` to remove all four places where Majordomo creates or transitions Jira Planning Tasks:

1. **Step 3, sub-step b**: Delete the entire sub-step that creates a Jira Planning Task (`POST .../issue` with title "Plan: ...") and captures `JIRA_PLANNING_KEY`.
2. **Step 3, sub-step f.2**: Remove `--external-ref "jira-${JIRA_PLANNING_KEY}"` from the Plan bead creation command. The Plan bead no longer links to a Jira task.
3. **Step 3 log**: Update "Issues processed" log entry to not reference Planning Task creation.
4. **Step 4, separation query**: Remove the "Plan tasks" category from the in_progress task separation. Only Stage tasks remain relevant to Step 4's Jira sync.
5. **Step 4, sub-step 5**: Remove the entire "For each Plan task (Planning Task)" block (approx. lines 131–143) that transitions Jira Planning Tasks to "Approved".
6. **Step 5, sub-step 3e**: Remove the `shared/jira-transition.sh ... "In Progress"` call for the Planning Task. Keep the beads claim and Jenkins trigger.
7. **Step 6, prelude text**: Reword the prelude (approx. line 225–226) that references "Step 4 writes the Jira transition to Approved" — that transition no longer happens.
8. **Step 6, sub-step i**: Remove the `shared/jira-transition.sh ... "Done"` call for the Jira Planning Task.

### Acceptance Criteria

- `majordomo/system-prompt.md` contains no calls to `shared/jira-transition.sh` for a Plan-task Jira key.
- `majordomo/system-prompt.md` contains no creation of a Jira task with "Plan:" in its title.
- `majordomo/system-prompt.md` no longer includes `--external-ref "jira-${JIRA_PLANNING_KEY}"` in the Plan bead creation.
- `make test` passes (shellcheck, bats, validate-prompts, dry-run, check-safety).

---

## Stage 2: Remove Jira references from the planning agent

### Description

Edit `minordomo-plan/system-prompt.md` to remove the parts that read the Jira Planning Task key and transition it to "In Review":

1. **Step 1**: Remove the `jira_task_id` extraction line (strip `"jira-"` prefix from `.external_ref`). Remove `jira_task_id` from the list of extracted fields. It is no longer needed.
2. **Spec Path Step 5**: Remove the entire step that calls `shared/jira-transition.sh "${jira_task_id}" "In Review"`. Remove the surrounding `If jira_task_id is empty, skip...` guard as well. Renumber the following step if needed.
3. **Run Log Format — `read_planning_task` step**: Remove the `"jira_task_id"` field from the example log entry.
4. **Run Log Format — `jira_transition` step**: Remove the `{"step": "jira_transition", ...}` example entry from the steps array.

### Acceptance Criteria

- `minordomo-plan/system-prompt.md` contains no call to `shared/jira-transition.sh`.
- `minordomo-plan/system-prompt.md` no longer extracts or references `jira_task_id`.
- The run log format example in the planning agent prompt does not include a `jira_transition` step.
- `make test` passes.

---

## Stage 3: Update documentation to reflect beads-only Plan task tracking

### Description

Update three documentation files to remove references to Jira Planning Tasks:

**`docs/WORKFLOWS.md`:**
1. **Jira Ticket Hierarchy**: Remove the `Planning Task (summary starts with "Plan:")` line from the hierarchy diagram. Epics now link directly to Implementation Tasks only.
2. **Task identity**: Remove the Planning Task entry (`issuetype = Task AND summary ~ "^Plan:"`).
3. **Planning Task status flow**: Remove the entire "Planning Task" status flow section (Open → In Progress → Needs Input → ... → Done table).
4. **Prioritization aside** (line ~106): Remove the parenthetical "Planning Tasks completing do not count" from the continuity criterion.

**`docs/agent-workflow-spec.md`:**
1. **GH Issue Ingestion**: Update the paragraph to say Majordomo creates a Jira Epic and beads tasks (Story + Plan), but not a Jira Planning Task.
2. **Planning Agent Loop**: Remove references to Jira status transitions for Planning Tasks (In Progress, Needs Input, In Review). Keep the behavioral description (research → spec PR or questions).
3. **Plan Approval Spinoff**: Remove the reference to transitioning the Jira Planning Task to Done.

**`CLAUDE.md`:**
1. **Task Identity & Ordering — Planning Tasks paragraph**: Update to clarify that Plan tasks exist in beads only. Remove the Python filter example for Jira `planning` tasks (beads filtering by title prefix is still valid for beads queries). Remove the JQL `summary ~ "Plan:"` guidance since Planning Tasks no longer exist in Jira.

### Acceptance Criteria

- `docs/WORKFLOWS.md` contains no Planning Task status flow table.
- `docs/agent-workflow-spec.md` does not describe creating a Jira Planning Task.
- `CLAUDE.md` Task Identity section does not instruct agents to query Jira for Plan tasks.
- `make test` passes.
