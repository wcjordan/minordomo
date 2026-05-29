# Implementation Plan: No longer create or check for Implementation Step tasks in Jira

GH Issue: https://github.com/wcjordan/minordomo/issues/201

## Overview

The pipeline currently creates Jira Implementation Tasks (child tasks under the Jira Epic) for
each stage in an approved spec. These tasks are linked to beads Stage tasks via `external_ref`
(e.g. `"jira-MDOMO-45"`) and transitioned through `Open → In Progress → In Review → Done` by
Majordomo and the worker agent.

This work removes all creation and lifecycle management of Jira Implementation Tasks. Jira Epics
(top-level, created during GH Issue ingestion) are unaffected. The beads-layer dependency graph
already handles stage ordering and eligibility; the Jira task shadow is no longer needed.

## Files Changed

- `majordomo/system-prompt.md` — Steps 4, 6, 8
- `minordomo-step/system-prompt.md` — Steps 1, 7, and environment section
- `docs/WORKFLOWS.md`
- `docs/agent-workflow-spec.md`
- `CLAUDE.md` (repo root and `minordomo/`)
- `README.md`
- `docs/GETTING_AROUND.md`
- `docs/FUTURE_WORK.md`

---

## Stage 1: Remove Jira Implementation Task lifecycle from system prompts

### Description

Remove all creation and status-transition logic for Jira Implementation Tasks from the Majordomo
and worker system prompts. After this stage, no new Jira task children are created under Epics,
and no beads Stage tasks are linked to Jira tasks via `external_ref`.

**Majordomo `majordomo/system-prompt.md`:**

- **Step 6h** — Delete the entire sub-step that creates one Jira Implementation Task per stage.
  Remove all references to `JIRA_IMPL_KEY_N`.
- **Step 6k** — Remove `--external-ref "jira-${JIRA_IMPL_KEY_N}"` from the `beads-write.sh create`
  command. The rest of step k (creating beads subtasks and wiring dependencies) stays.
- **Step 4b** — Remove the extraction of `jira_task_key` from `external_ref` and the sub-step that
  transitions the Jira task to Done. The step still closes beads Stage tasks when their PR is
  merged; only the Jira transition is removed.
- **Step 4 run log** — Rename the `tasks_transitioned` counter to `beads_tasks_closed` in both
  the step instructions and the example run log entry at the bottom of the file
  (`"tasks_transitioned": <N>` → `"beads_tasks_closed": <N>`).
- **Step 8 sub-step 8** — Remove the `(write — keep)` sub-step that transitions the Jira task to
  In Progress and the `jira_task_key` extraction above it. The rest of Step 8 (claiming the beads
  task, triggering Jenkins) stays.

**Worker `minordomo-step/system-prompt.md`:**

- **Step 1** — Remove the `jira_task_id` extraction line (`from .external_ref, strip the "jira-"
  prefix`). Remove the bullet from the "Extract:" list and the example in the run log
  (`"jira_task_id": "MDOMO-45"`).
- **Step 7 (Transition Jira Task to In Review)** — Remove this step entirely.
- **Run log format** — Remove the `jira_transition` step from the example JSON.
- **Environment section** — Remove the `Jira: write-only via REST API (...)` line. The worker
  no longer makes any Jira writes (the needs-input flow uses `apply-needs-input.sh` and
  `get-epic-key.sh` but not `jira-transition.sh`).

### Acceptance Criteria

- `majordomo/system-prompt.md` Step 6h is gone; no `JIRA_IMPL_KEY_N` variable appears anywhere
  in Step 6.
- Step 6k's `beads-write.sh create` command has no `--external-ref` flag.
- `majordomo/system-prompt.md` Step 4 contains no reference to `jira_task_key` or
  `jira-transition.sh`. The step-level log field is `beads_tasks_closed` (not `tasks_transitioned`).
- `majordomo/system-prompt.md` Step 8 has no `jira_task_key` extraction and no
  `jira-transition.sh "In Progress"` call.
- `minordomo-step/system-prompt.md` Step 1 does not mention `jira_task_id` or `external_ref`.
- `minordomo-step/system-prompt.md` has no Step 7.
- Worker run log example does not contain a `jira_transition` step or `jira_task_id` field.
- Worker environment section does not advertise Jira REST API write access.
- `make test` passes.

---

## Stage 2: Update WORKFLOWS.md and agent-workflow-spec.md

### Description

Update the two primary workflow documentation files to reflect that Jira Implementation Tasks
no longer exist in the pipeline.

**`docs/WORKFLOWS.md`:**

- **Jira Ticket Hierarchy section** — Remove "Implementation Tasks (one per stage from the
  approved plan)" from the hierarchy tree. Update the prose below it: remove the sentence
  "Implementation Tasks are spun off by Majordomo when the Plan bead reaches `Approved` (Step 5).
  One task per `## Stage N:` section in the spec doc." and the "Task identity" bullet for
  Implementation Tasks.
- **Jira Status Flows → Implementation Task section** — Remove this entire subsection
  (`Open → Ready → In Progress → In Review → Done` table).
- **Beads Status Flows → Stage section** — In the prose after the table, remove the sentence
  "Stage tasks are identified by the `Stage N:` title prefix and mirror a Jira Implementation Task
  via `external_ref`." Also remove "external_ref" from the `closed` status description if present.
- **Spec Documents section** — Remove the sentence "Each `## Stage N:` section in the spec yields
  one Jira Implementation Task. The stage number is not stored in the Jira title — only the text
  after `## Stage N:` is used. Stage ordering is determined by Jira rank (`customfield_10019`),
  which reflects creation order." Replace with: "Stage ordering is determined by the beads
  dependency chain wired by Majordomo during Plan Approval Spinoff (Step 6l); each stage N depends
  on stage N−1."
- **Prioritization section** — Update the two paragraphs that reference Jira `status = Ready` and
  Jira rank ordering. Specifically, rewrite the paragraph starting "Beads (`bd ready`) is used here
  rather than Jira `status = Ready` because..." to reflect that Step 7 (Promote to Ready) is
  permanently removed (not just a migration no-op). Remove references to Jira rank ordering for
  implementation task selection — the ordering is now entirely beads-based.

**`docs/agent-workflow-spec.md`:**

- **Plan Approval Spinoff section** (line 23) — Replace "creates one Jira Implementation Task per
  `## Stage N:` section. Implementation Tasks are created in stage order; Jira rank reflects stage
  sequence and is used for ordering." with "creates one beads Stage task per `## Stage N:` section.
  Tasks are created in stage order and wired with blocking dependencies (stage N depends on N−1)
  so `bd ready` surfaces them in sequence."
- **Task Prioritization & Ready Promotion section** (line 27) — Rewrite to remove all Jira
  status/rank references. New text should describe beads-based selection: unblocked, unclaimed
  Stage tasks are surfaced by `bd ready`; Majordomo selects by continuity, priority, then beads
  creation order.
- **Worker Agent section** (line 31) — Remove "and transitioning the Jira ticket to In Review".
- **PR Sync section** (line 35) — Update "Majordomo auto-transitions Jira tickets when humans
  merge planning or implementation PRs" to only reference planning PRs (not implementation PRs),
  since only the Epic is transitioned on implementation PR merge (via Step 4 close, not Jira task).
  Actually the implementation PR merge closes the beads task and does NOT transition a Jira task
  (after Stage 1). Clarify accordingly.
- **Majordomo Run Sequence list** (lines 55-63) — Remove "5. Plan Approval Spinoff → create
  Implementation Tasks from approved spec docs" and "6. Promote eligible Implementation Tasks to
  Ready". Update to reflect current step numbering.

### Acceptance Criteria

- `docs/WORKFLOWS.md` contains no "Implementation Task" status flow table or `Open → Ready →
  In Progress → In Review → Done` status chain.
- `docs/WORKFLOWS.md` Jira Ticket Hierarchy section lists only Epics (no Implementation Task
  children).
- `docs/WORKFLOWS.md` Stage section does not mention `external_ref` or Jira task mirroring.
- `docs/WORKFLOWS.md` Spec Documents section describes beads dependency chain as the ordering
  mechanism, not Jira rank.
- `docs/agent-workflow-spec.md` Plan Approval Spinoff section describes beads Stage task creation
  without mentioning Jira.
- `docs/agent-workflow-spec.md` Worker Agent section does not mention Jira ticket transitions for
  implementation tasks.
- `make test` passes.

---

## Stage 3: Update CLAUDE.md, README.md, GETTING_AROUND.md, and FUTURE_WORK.md

### Description

Update the remaining documentation files to remove references to Jira Implementation Tasks.

**`CLAUDE.md` (repo root) and `minordomo/CLAUDE.md` (identical):**

- **Task Identity & Ordering section** — Change "Implementation Tasks: Every Jira Task and every
  beads task that does not start with `Plan:`." to "Implementation Tasks: Every beads task that
  does not start with `Plan:` or `Story:`."
- Remove the sentence "Stage ordering within an Epic: Use Jira rank (`customfield_10019`) — lower
  lexicographic value = created earlier = lower stage number. Tasks are created in stage order by
  the Plan Approval Spinoff step (Step 5), so Jira rank reliably reflects stage sequence." Replace
  with: "Stage ordering within an Epic: determined by the beads dependency chain — each Stage N
  task depends on Stage N−1, so `bd ready` surfaces them in sequence."

**`README.md`:**

- Lines 20-21: Replace "3. Spins off Implementation Tasks from approved plans" and
  "4. Promotes eligible Implementation Tasks to Ready" with a single updated bullet that reflects
  the current behavior (e.g. "3. Spins off beads Stage tasks from approved plans; stages are
  sequenced via dependency chain").

**`docs/GETTING_AROUND.md`:**

- Table row "Feature→main PRs": Update "Auto-opened when all Implementation Tasks are Done;
  includes doc cleanup" — "Implementation Tasks" here means beads Stage tasks; reword to
  "Auto-opened when all Stage tasks are closed; includes doc cleanup".
- Table row "Worker agents": Update "Branch, implement, open PR, transition ticket" — remove
  "transition ticket" since the worker no longer transitions a Jira ticket.

**`docs/FUTURE_WORK.md`:**

- Line 89: Update the future stale-task sweep section. It describes finding Implementation Tasks
  in "In Progress" for more than 12 hours and resetting them to "Ready". Since Jira task states
  are gone, rewrite to describe the beads-layer equivalent: finding beads Stage tasks in
  `in_progress` status for more than 12 hours and resetting them to `open`.
- Lines 111-112: Update the stale-task worker contract description to use beads status names
  (`open` / `in_progress`) instead of Jira status names (`Ready` / `In Progress`).
- Line 120: "Parallel workers" future item mentions "`In Progress` transition is the atomic claim"
  — update to reflect that the `beads-write.sh update --claim` is the atomic claim operation.

### Acceptance Criteria

- Neither `CLAUDE.md` nor `minordomo/CLAUDE.md` mentions `customfield_10019` or Jira rank for
  stage ordering. Both define Implementation Tasks using only beads task title prefix.
- `README.md` pipeline overview does not mention "promote to Ready" as a separate step.
- `docs/GETTING_AROUND.md` worker agent row does not say "transition ticket".
- `docs/FUTURE_WORK.md` stale-task sweep description uses beads status names, not Jira status
  names.
- `make test` passes.
