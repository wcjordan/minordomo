# Implementation Plan: MDOMO-7 — Stage 4: Majordomo Prioritization, Ready Promotion, and Feature→Main PRs

## Overview

This plan implements Steps 6, 7, and 8 of `majordomo/system-prompt.md`, replacing the three "not yet implemented" stubs with full logic. After this plan is complete, Majordomo will autonomously evaluate open implementation tasks, promote eligible ones to Ready, launch a worker, and open the feature→main PR when all subtasks of an Epic are Done.

The work is split into three stages, one per Majordomo step, each averaging ~30 minutes of implementation.

---

## Stage 1: Promote Open Implementation Tasks to Ready

### Description

Replace the Step 6 stub in `majordomo/system-prompt.md` with full promotion logic.

**What Majordomo must do in Step 6:**

1. Query Jira for all Implementation Tasks in status `Open` across all configured projects.
   - Implementation Tasks are `issuetype = Task` whose summary does **not** start with `Plan:`.
   - JQL: `project in (<jira_keys>) AND issuetype = Task AND summary !~ "^Plan:" AND status = Open`

2. For each Open Implementation Task:
   a. Fetch all sibling tasks under the same parent Epic (`parent = <EPIC_KEY>`), filtering to Implementation Tasks (exclude the Planning Task).
   b. Determine ordering: sort siblings by Jira rank field (`customfield_10019` ascending). Lower rank = earlier stage = "prior".
   c. Collect all siblings with rank lower than the current task. Check that all of those are `Done`.
   d. Check that no sibling (any rank) is currently `In Progress` or `In Review`.
   e. If both checks pass: promote the task to `Ready` by calling `GET /rest/api/3/issue/{key}/transitions` to find the transition ID for `Ready`, then `POST /rest/api/3/issue/{key}/transitions`.

3. Log in the step result:
   - `tasks_evaluated`: total Open implementation tasks checked
   - `tasks_promoted`: count of tasks transitioned to Ready
   - `tasks_skipped`: count skipped with reasons (prior not done, sibling in flight)
   - Any per-task errors (log and continue; do not abort the whole step)

4. Replace the current stub log line with the real result.

**Note on first-stage tasks:** If a task has no prior siblings (lowest rank in the Epic), only the second check applies (no sibling In Progress/In Review).

### Acceptance Criteria

- Step 6 no longer emits `"status": "skipped"` — it emits `"status": "ok"` with real counts.
- An Open Implementation Task whose prior siblings are all Done and no sibling is in flight is transitioned to `Ready`.
- An Open Implementation Task whose prior sibling is not Done remains `Open` (not promoted).
- An Open Implementation Task under an Epic with a sibling `In Progress` or `In Review` is not promoted.
- First-stage tasks (no prior siblings) are promoted if no sibling is in flight.
- Errors on individual tasks are logged but do not abort the step.
- The Majordomo run log includes `tasks_evaluated`, `tasks_promoted`, and `tasks_skipped` in the step 6 entry.

---

## Stage 2: Launch Worker Agent with Prioritization

### Description

Replace the Step 7 stub in `majordomo/system-prompt.md` with full worker-launch logic.

**What Majordomo must do in Step 7:**

1. If `planning_agent_launched` is `true` from Step 4: log `{"step": "launch_worker", "status": "skipped", "message": "planning agent launched this run"}` and continue.

2. Otherwise:
   a. Query Jira for all Implementation Tasks in status `Ready` across all configured projects.
   b. For each Ready task, fetch its parent Epic to collect:
      - All sibling Implementation Tasks and their statuses
      - Epic priority labels (`P0`, `P1`, `P2`)
      - Epic Jira rank (`customfield_10019`)
   c. Exclude any task whose parent Epic has a sibling currently `In Progress` or `In Review` — launching a second worker on the same Epic would cause conflicts.
   d. Rank the remaining candidates:
      1. Tasks whose parent Epic has other Implementation Tasks already `Done` come first (continuity — the Epic is making progress)
      2. Among ties: Epic with highest priority label (`P0` > `P1` > `P2` > unlabelled)
      3. Among ties: Epic with lowest Jira rank value (ascending lexicographic = manual ordering)
   e. Select the top-ranked task.
   f. Transition it to `In Progress` via Jira transitions API.
   g. Trigger the worker Jenkins job:
      ```
      curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
        "http://jenkins.${ROOT_DOMAIN}/job/majordomo-worker/job/${BASE_BRANCH}/buildWithParameters?JIRA_TASK_ID=<task_id>"
      ```
   h. Log: `{"step": "launch_worker", "status": "ok", "task_id": "<id>", "worker_launched": true}`

3. If no Ready tasks exist:
   - Log: `{"step": "launch_worker", "status": "ok", "worker_launched": false, "message": "no Ready tasks found"}`

### Acceptance Criteria

- Step 7 no longer emits `"status": "skipped"` (unless a planning agent was launched this run).
- When `planning_agent_launched` is true, Step 7 logs a skip with the reason.
- Ready tasks whose Epic has a sibling `In Progress` or `In Review` are excluded from selection.
- When Ready tasks exist after exclusions, Majordomo selects one using the prioritization order and transitions it to `In Progress`.
- The worker Jenkins job is triggered via HTTP POST with the selected task ID.
- The run log includes `worker_launched: true/false` and `task_id` when a task is selected.
- When no Ready tasks remain after exclusions, the step completes with `worker_launched: false`.
- Prioritization is applied correctly: epics with Done siblings first, then priority label, then Epic rank.

---

## Stage 3: Open Feature→Main PRs for Completed Epics

### Description

Replace the Step 8 stub in `majordomo/system-prompt.md` with full feature→main PR logic.

**What Majordomo must do in Step 8:**

1. For each project in config (repo + jira_key):
   a. Query Jira for all Epics in the project:
      `project = <jira_key> AND issuetype = Epic`
   b. For each Epic:
      - Fetch all child tasks (`parent = <EPIC_KEY>`).
      - Separate Planning Tasks (summary starts with `Plan:`) from Implementation Tasks.
      - Skip Epics with zero Implementation Tasks (spinoff not done yet or Epic has no stages).
      - Skip Epics where any Implementation Task is **not** `Done` (story not complete).
      - Check for an existing open PR: `gh pr list --repo wcjordan/<repo> --base main --head feature/<EPIC_KEY> --state open --json number`
      - Skip if an open PR already exists.
   c. For eligible Epics:
      - Extract GH Issue URL from Epic description (format: `GitHub Issue: <url>`).
      - Build a PR title: the Epic summary.
      - Build a PR body: a summary of what was delivered, referencing the GH Issue URL. Include a bullet list of the implementation task titles.
      - Open the PR: `gh pr create --repo wcjordan/<repo> --base main --head feature/<EPIC_KEY> --title "..." --body "..."`
      - Log the PR URL.
      - Transition the Epic to `In Review` via Jira transitions API.

2. Log in the step result:
   - `epics_checked`: total Epics evaluated
   - `prs_opened`: count of PRs successfully opened
   - `epics_skipped`: count skipped (incomplete, no impl tasks, PR already open)
   - Any per-Epic errors (log and continue)

3. Replace the current stub log line with the real result.

### Acceptance Criteria

- Step 8 no longer emits `"status": "skipped"` — it emits `"status": "ok"` with real counts.
- When all Implementation Tasks of an Epic are `Done` and no feature→main PR is open, a PR is opened from `feature/<EPIC_KEY>` to `main`.
- The PR description references the originating GH Issue URL (from the Epic description).
- The PR description includes a summary of what the Epic delivered (implementation task titles at minimum).
- Epics with any non-Done Implementation Task are skipped.
- Epics with an existing open feature→main PR are skipped (idempotent).
- Epics with no Implementation Tasks are skipped.
- The run log includes `epics_checked`, `prs_opened`, and `epics_skipped`.
- After opening the PR, the Epic is transitioned to `In Review` in Jira.
- Majordomo never merges the PR — only opens it for human review.
