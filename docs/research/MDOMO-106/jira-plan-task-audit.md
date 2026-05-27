# Jira Plan Task Audit — MDOMO-106

## Objective

Remove all Jira interactions specific to "Plan:" tasks. Plan tasks will exist only in beads going forward.

## Files to Change

### `majordomo/system-prompt.md`

**Step 3 (lines 62–84):**
- Sub-step b: Creates a Jira Planning Task (`POST .../issue` with title "Plan: ..."). Remove this entirely.
- Sub-step f.2: Plan bead creation includes `--external-ref "jira-${JIRA_PLANNING_KEY}"`. Remove this flag.
- Log entry references "Planning Task created": update to just mention beads tasks created.

**Step 4 (lines 100–149):**
- Lines 106–108: Separates in_progress tasks into Stage tasks and Plan tasks. Remove Plan separation.
- Sub-step 5 (lines 131–143): For each Plan task, transitions Jira Planning Task to "Approved". Remove entire sub-step 5.

**Step 5 (lines 153–219):**
- Sub-step 3e (lines 206–209): Transitions Jira Planning Task to "In Progress" before Jenkins trigger. Remove Jira transition; keep beads claim and Jenkins trigger.

**Step 6 (lines 223–278):**
- Prelude text (lines 225–226): References "Step 4 writes the Jira transition to Approved". Reword.
- Sub-step i (line 254): Transitions Jira Planning Task to Done. Remove.

### `minordomo-plan/system-prompt.md`

**Step 1 (lines 34–38):**
- Extracts `jira_task_id` from `.external_ref` field. Remove this extraction.

**Spec Path Step 5 (lines 134–138):**
- Calls `shared/jira-transition.sh "${jira_task_id}" "In Review"`. Remove entire step.
- Step numbering: renumber subsequent steps or remove step 5 and adjust numbering.

**Run Log Format (lines 155–162):**
- `read_planning_task` step includes `jira_task_id` field: remove.
- `jira_transition` step: remove from example log.

### `docs/WORKFLOWS.md`

- Jira Ticket Hierarchy (lines 10–13): Remove "Planning Task" from hierarchy.
- Task identity section (lines 19–22): Remove Planning Task reference.
- Planning Task status flow section (lines 29–40): Remove entirely.
- Prioritization aside (line 106): "Planning Tasks completing do not count" — remove.

### `docs/agent-workflow-spec.md`

- GH Issue Ingestion (lines 14–16): Update to not mention Planning Task creation in Jira.
- Planning Agent Loop (lines 18–20): Remove references to Jira status transitions.
- Plan Approval Spinoff (lines 22–24): Remove Jira Planning Task Done transition.

### `CLAUDE.md`

- Task Identity section (lines 97–109): Remove the Planning Tasks concept or clarify it's beads-only now.

## Decision: Stale external_ref on existing Plan beads

Existing Plan beads (e.g. minordomo-x9o.1) carry `external_ref: "jira-MDOMO-88"` etc. from runs before this change. These can be left as-is — nothing reads them for Plan task Jira operations after this change. No retroactive cleanup needed.

## Tests

Tests that may be affected:
- `test/bats/jira-transition.bats` — tests the `shared/jira-transition.sh` script itself (not the Plan-specific behavior). No changes needed.
- `test/validate-prompts.py` — validates static file paths and Jenkins job names. No Plan-specific checks.
- `test/dry-run.sh` — references `Plan: Test feature` as a beads task title. This is about the beads title format, not Jira interactions. No change needed.

`make test` (shellcheck + bats + validate-prompts.py + dry-run + check-safety) should pass after each stage.
