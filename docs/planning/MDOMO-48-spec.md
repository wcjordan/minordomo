# MDOMO-48: Task Selection Enhancement — Implementation Plan

## Stage 1: Fix `has_done_siblings` to exclude planning tasks in Step 8

### Description

The current ranking in Majordomo Step 8 ("Rank candidates") sorts by `has_done_siblings` first (continuity heuristic — prefer epics already in motion), then `priority_order`, then `epic_rank`. This ordering is correct and should be preserved.

The bug is in how `has_done_siblings` is computed: it currently counts any sibling task in Done status, including Planning Tasks (`Plan:` prefix). A planning task completing should not be treated as the epic being "in progress" — only completed Implementation Tasks (tasks whose summary does **not** start with `Plan:`) should set this flag to `true`.

Fix the `has_done_siblings` computation so it filters to Implementation Tasks only. The sort order itself does not change. Also update `docs/WORKFLOWS.md` to clarify that continuity is the primary criterion and that it is based on completed implementation work only.

Changes to `majordomo/system-prompt.md` Step 8, step 6 (or wherever `has_done_siblings` is computed):

**Before:**
```
has_done_siblings: true if any sibling task in the same Epic has status Done
```

**After:**
```
has_done_siblings: true if any sibling Implementation Task (summary does NOT start with "Plan:")
                   in the same Epic has status Done
```

The sort order in step 7 remains unchanged:
```
Sort by: `has_done_siblings` descending (`true` first — prefer continuing an epic already in motion),
then `priority_order` ascending (0=P0 best),
then `epic_rank` ascending (lexicographic).
```

Changes to `docs/WORKFLOWS.md`, Prioritization section, "Selecting a worker target" bullet list — clarify that continuity is first and is based on completed implementation tasks only:

**Before (Step 7):**
1. Tasks whose Epic has other Implementation Tasks already `Done` (continuity)
2. Epic priority label: `P0` > `P1` > `P2` > unlabelled
3. Epic Jira rank (`customfield_10019`, ascending lexicographic)

**After:**
1. Tasks whose Epic has at least one Implementation Task (non-`Plan:`) already `Done` (continuity — Planning Tasks completing do not count)
2. Epic priority label: `P0` > `P1` > `P2` > unlabelled
3. Epic Jira rank (`customfield_10019`, ascending lexicographic)

### Acceptance Criteria

- In `majordomo/system-prompt.md` Step 8, `has_done_siblings` is computed using only Implementation Tasks (summaries not starting with `Plan:`) with status Done; Planning Tasks are excluded
- The sort order in Step 8 step 7 remains `has_done_siblings` descending → `priority_order` ascending → `epic_rank` ascending
- In `docs/WORKFLOWS.md`, the Prioritization section "Selecting a worker target" lists continuity as the first criterion (with explicit note that planning task completion does not count) and epic priority as second
- `make test` passes

---

## Stage 2: Propagate Epic priority to implementation beads at Step 6 creation

### Description

Step 6 ("Plan Approval Spinoff") creates beads implementation subtasks without a `--priority` flag, so they all default to P2 regardless of the Epic's actual priority. Step 3 already extracts priority from GH issue labels and sets it on planning beads — Step 6 needs to do the same for implementation beads using the parent Epic's Jira labels.

This matters because Stage 3's priority guard (below) reads priority directly from beads tasks to avoid querying Jira for each candidate. If implementation beads all default to P2, the guard can't distinguish a P0 implementation task from a P2 one.

Changes to `majordomo/system-prompt.md` Step 6, within the per-approved-task loop (step 2):

Add a new step before the current beads subtask creation step (2i), after finding the beads planning task (2h):

**New step 2i — Fetch Epic priority for beads tasks:**
```
i. Fetch the parent Epic's labels to determine priority:
   GET ${JIRA_URL}/rest/api/3/issue/<EPIC_KEY>?fields=labels
   (The Epic key is the parent of the approved planning task — available from fields.parent.key.)
   Look for the first label whose name exactly matches P0, P1, P2, P3, or P4.
   Set EPIC_PRIORITY to the numeric value (0 for P0, 1 for P1, 2 for P2, 3 for P3, 4 for P4).
   Default to 2 (P2) if no matching label found.
   On fetch error: log a per-epic error, set EPIC_PRIORITY = 2, and continue.
```

**Updated step 2j (was 2i) — Create beads subtasks with priority:**

Before:
```bash
BEADS_STAGE_N_ID=$(bd create "Stage N: <title>" --parent "$BEADS_PLAN_ID" --json | jq -r '.id')
```

After:
```bash
BEADS_STAGE_N_ID=$(bd create "Stage N: <title>" --parent "$BEADS_PLAN_ID" --priority "$EPIC_PRIORITY" --json | jq -r '.id')
```

(Step 2k, wiring blocking dependencies, is unchanged — was step 2j.)

### Acceptance Criteria

- In `majordomo/system-prompt.md` Step 6, before creating beads implementation subtasks, the parent Epic's Jira labels are fetched and a numeric priority (0–4, default 2) is derived using the same P0–P4 label matching as Step 3
- Each `bd create "Stage N: <title>"` call includes `--priority "$EPIC_PRIORITY"`
- On Epic label fetch error, priority defaults to 2 and the error is logged; beads task creation proceeds
- `make test` passes

---

## Stage 3: Add planning task priority guard in Step 5

### Description

Majordomo Step 5 launches a planning agent whenever a planning task is available, regardless of what implementation tasks are queued. This causes a P2 planning task to preempt P0 or P1 implementation work, because Step 8 is unconditionally skipped whenever Step 5 launches a planning agent.

Fix: after selecting the best eligible planning task candidate (by epic priority), check whether any higher-priority implementation tasks are available via beads (`bd ready`). If the best available implementation task has a strictly better priority than the planning task candidate, skip launching the planning agent this run and let Step 8 handle the implementation work instead.

"Strictly better" means the implementation task's beads priority (integer, 0=P0 best) is numerically lower than the planning task's beads priority. Equal priorities or no beads-eligible implementation tasks → planning agent proceeds.

**Why beads instead of Jira `status = Ready`:** Step 7 (Promote to Ready) is now a no-op in the Beads migration — Jira implementation tasks stay in `Open` until a worker claims them. Querying Jira for `status = Ready` in Step 5 would almost always return zero results, making the guard ineffective. `bd ready` correctly surfaces all unblocked, unclaimed implementation tasks regardless of Jira status.

**Implementation details for Step 5 in `majordomo/system-prompt.md`:**

After step 3 ("Pick the highest-priority eligible task…"), insert a new step 3a before triggering the Jenkins job:

```
3a. Priority guard — check for higher-priority implementation work in beads:
  a. Query beads for eligible implementation tasks:
       bd ready --json | jq '[.[] | select(.title | startswith("Plan:") | not)]'
  b. Compute best_impl_priority: the minimum .priority value across all returned tasks
     (beads priority is an integer, 0=P0 best). If no tasks returned, best_impl_priority = 4.
  c. Compute planning_priority: the .priority value of the selected planning task's beads record.
     Retrieve it by looking up the beads planning task by title (same lookup used in step 4):
       bd list --json | jq -r --arg title "<fields.summary>" \
         '[.[] | select(.title == $title)] | first | .priority // 2'
     If the beads planning task is not found, fall back to deriving priority from epic_labels
     (0 if "P0" in labels, 1 if "P1", 2 if "P2", 3 otherwise).
  d. If best_impl_priority < planning_priority:
     - Log: {"decision": "skip_planning_agent", "reason": "higher_priority_impl_work_available",
              "planning_priority": <value>, "best_impl_priority": <value>}
     - Set planning_agent_launched: false
     - Skip to Step 6 (do not transition the planning task or trigger Jenkins)
  e. Otherwise: proceed with planning agent launch as before.
```

Also update `docs/WORKFLOWS.md` under "Prioritization" to document that planning agent launch is deferred when higher-priority implementation tasks are available in beads.

### Acceptance Criteria

- In `majordomo/system-prompt.md` Step 5, there is an explicit priority guard step (3a or equivalent) that:
  - Runs `bd ready --json` filtered to non-`Plan:` tasks to find eligible implementation tasks
  - Reads priority directly from beads task records (not by fetching Jira Epic labels per task)
  - Skips planning agent launch if any implementation task has a strictly lower (better) numeric priority than the planning task
  - Logs the skip decision with both priority values
- When implementation tasks have equal or lower priority than the planning task, the planning agent launches as before
- When no beads-eligible implementation tasks exist, the planning agent launches as before
- `docs/WORKFLOWS.md` documents the priority guard behavior and explains why beads is used instead of Jira `status = Ready`
- `make test` passes
