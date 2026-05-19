# MDOMO-48: Task Selection Enhancement — Implementation Plan

## Stage 1: Fix implementation task priority ordering in Step 8

### Description

The current ranking in Majordomo Step 8 ("Rank candidates") sorts by `has_done_siblings` first (continuity heuristic), then `priority_order`, then `epic_rank`. This causes P1 epics with some Done siblings to rank ahead of P0 epics with no Done siblings — a clear violation of intended priority ordering.

Fix the sort order so that epic priority is always the primary criterion. Continuity is only used as a tiebreaker within the same priority band. Also update `docs/WORKFLOWS.md` to document the corrected ordering.

Changes to `majordomo/system-prompt.md` Step 8, step 7 "Rank candidates":

**Before:**
```
Sort by: `has_done_siblings` descending (`true` first),
then `priority_order` ascending (0=P0 best),
then `epic_rank` ascending (lexicographic).
```

**After:**
```
Sort by: `priority_order` ascending (0=P0 best),
then `has_done_siblings` descending (`true` first — prefer continuing an epic already in motion),
then `epic_rank` ascending (lexicographic).
```

Changes to `docs/WORKFLOWS.md`, Prioritization section, "Selecting a worker target" bullet list:

**Before (Step 7):**
1. Tasks whose Epic has other Implementation Tasks already `Done` (continuity)
2. Epic priority label: `P0` > `P1` > `P2` > unlabelled
3. Epic Jira rank (`customfield_10019`, ascending lexicographic)

**After:**
1. Epic priority label: `P0` > `P1` > `P2` > unlabelled
2. Tasks whose Epic has other Implementation Tasks already `Done` (continuity — tiebreaker within same priority)
3. Epic Jira rank (`customfield_10019`, ascending lexicographic)

### Acceptance Criteria

- In `majordomo/system-prompt.md` Step 8 step 7, the sort order is `priority_order` ascending → `has_done_siblings` descending → `epic_rank` ascending
- In `docs/WORKFLOWS.md`, the Prioritization section "Selecting a worker target" lists epic priority as the first criterion, continuity as second, and Jira rank as third
- `make test` passes

---

## Stage 2: Add planning task priority guard in Step 5

### Description

Majordomo Step 5 launches a planning agent whenever a planning task is available, regardless of what implementation tasks are queued. This causes a P2 planning task to preempt P0 or P1 implementation work, because Step 8 is unconditionally skipped whenever Step 5 launches a planning agent.

Fix: after selecting the best eligible planning task candidate (by epic priority), check whether any higher-priority implementation tasks are currently in `Ready` status. If the best available implementation task has a strictly better epic priority than the planning task candidate, skip launching the planning agent this run and let Step 8 handle the implementation work instead.

"Strictly better" means: the implementation task's `priority_order` (0=P0, 1=P1, 2=P2, 3=other) is numerically lower than the planning task's `priority_order`. Equal priorities or no Ready implementation tasks → planning agent proceeds.

**Implementation details for Step 5 in `majordomo/system-prompt.md`:**

After step 3 ("Pick the highest-priority eligible task…"), insert a new step 3a before triggering the Jenkins job:

```
3a. Priority guard — check for higher-priority implementation work:
  a. Query Jira for all Ready implementation tasks across all configured projects:
     JQL: project in (<jira_keys>) AND issuetype = Task AND summary !~ "Plan:" AND status = Ready
     Fields: parent
  b. For each Ready implementation task, fetch its parent Epic to get `epic_labels`
     (same Epic fetch as Step 8.5b — GET ${JIRA_URL}/rest/api/3/issue/<EPIC_KEY>?fields=labels)
  c. Compute `best_impl_priority`: minimum of (0 if "P0" in labels, 1 if "P1", 2 if "P2", 3 otherwise)
     across all Ready implementation tasks. If no Ready implementation tasks exist, `best_impl_priority = 4`.
  d. Compute `planning_priority`: 0 if "P0" in planning task's epic_labels, 1 if "P1", 2 if "P2", 3 otherwise.
  e. If `best_impl_priority` < `planning_priority`:
     - Log: {"decision": "skip_planning_agent", "reason": "higher_priority_impl_work_ready",
              "planning_priority": <value>, "best_impl_priority": <value>}
     - Set `planning_agent_launched: false`
     - Skip to Step 6 (do not transition the planning task or trigger Jenkins)
  f. Otherwise: proceed with planning agent launch as before.
```

Also update `docs/WORKFLOWS.md` under "Prioritization" to document that planning agent launch is deferred when higher-priority implementation tasks are Ready.

### Acceptance Criteria

- In `majordomo/system-prompt.md` Step 5, there is an explicit priority guard step (3a or equivalent) that:
  - Queries Jira for Ready implementation tasks
  - Compares best implementation task epic priority against the selected planning task epic priority
  - Skips planning agent launch if a strictly higher-priority (lower `priority_order`) implementation task is Ready
  - Logs the skip decision with both priority values
- When implementation tasks have equal or lower priority than the planning task, the planning agent launches as before
- When no Ready implementation tasks exist, the planning agent launches as before
- `docs/WORKFLOWS.md` documents the priority guard behavior
- `make test` passes
