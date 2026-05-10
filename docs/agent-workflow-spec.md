# Claude Code Agent Workflow Spec

## Overview

A multi-agent system for autonomously picking up, planning, and implementing development tasks. The system is orchestrated by a **Majordomo agent** that runs on a schedule, evaluates work across projects, manages Claude usage limits, and launches **worker agents** to execute implementation tasks. A separate **planning agent** handles ticket grooming through an iterative human Q&A loop.

The stages are ordered so that the system can take over building itself as early as possible. After Stage 3, a GH Issue can be filed for the remaining stages and the system will plan and implement them autonomously.

For system design, Jira workflows, branching model, and repo structure, see [`docs/GETTING_AROUND.md`](GETTING_AROUND.md).

---

## ✅ Completed Stages

### Stage 1 — Foundation & Trust Boundaries ✅

- GH Issue allowlist filter via `shared/config.yaml`
- Jira project schema (Epic → Story → Task hierarchy, all statuses)
- Majordomo skeleton as a non-interactive `claude -p` Jenkins job

### Stage 2 — GH Issue Ingestion & Minimal Worker ✅

- Majordomo polls GH Issues → creates Jira Epics + Planning Tasks
- `jira-epic-created` label as idempotency gate
- Worker agent: reads Jira task, checks out feature/task branch, implements, opens PR, transitions to In Review

### Stage 3 — Planning Agent Loop ✅

- Majordomo identifies Open planning tasks → transitions to In Progress → triggers planning agent Jenkins job
- Planning agent: reads task, does research, posts questions (→ Needs Input) or produces spec doc PR (→ In Review)
- Human Q&A flow via Jira comments
- Plan Approval Spinoff: on Approved planning task, Majordomo reads spec doc and creates one Implementation Task per stage

### Stage 4 — Majordomo Prioritization, Ready Promotion & Feature→Base PRs ✅

- Step 6: promotes eligible Open Implementation Tasks to Ready (prior siblings all Done, no sibling In Progress/In Review)
- Step 7: selects top Ready task using prioritization (continuity → Epic priority → Jira rank), transitions to In Progress, triggers worker
- Step 8: opens feature→base PR when all Implementation Tasks of an Epic are Done; transitions Epic to In Review

---

## ✦ Handoff Point

After Stage 3, file a GH Issue describing Stages 5–7. The Majordomo will ingest it, the Planning Agent will research and produce a spec, and the Worker will implement each stage. The specs below serve as the starting point for that work.

---

## Stage 5 — Usage Limits & Scheduling

**Goal:** Respect Claude usage limits and run only at appropriate times.

### 5.1 Usage Check

Before launching any worker, Majordomo:
- Makes an OAuth request to `https://api.anthropic.com/api/oauth/usage` to retrieve weekly usage
  - Reference implementation: [`claude_quota.py`](https://github.com/slopware/claude-quota/blob/main/claude_quota.py)
  - **Note:** This endpoint is unofficial and undocumented; verify it works before relying on it and handle gracefully if it changes
- Checks weekly usage against a configurable threshold (default: **50%**)
- If usage ≥ threshold → logs decision, exits without launching a worker

### 5.2 Time-of-Day Gating

Majordomo enforces a configurable schedule:

Config in `shared/config.yaml`:
```yaml
schedule:
  allowed_days: [Mon, Tue, Wed, Thu, Fri]
  allowed_hours: ["00:00-08:00", "18:00-23:59"]
  weekend_override: false
```

If outside the allowed window → log decision, exit 0 without launching any agents.

### 5.3 Jenkins Scheduling

- Majordomo runs as a Jenkins job on a defined cron schedule (currently triggered manually)
- Jenkins configured with **no concurrency** (one Majordomo run at a time — already in place via `disableConcurrentBuilds`)
- Jenkinsfile isolates all scheduling and trigger logic so migration to GH Actions is straightforward

### Acceptance Criteria

- Step 2 no longer emits `"status": "skipped"` — it checks usage and schedule and exits or proceeds accordingly
- When usage ≥ threshold, Majordomo logs the decision and exits 0 without launching any agents
- When current time is outside allowed windows, Majordomo logs the decision and exits 0
- The `schedule` and `usage` config blocks in `shared/config.yaml` are respected
- `majordomo/Jenkinsfile` has a cron trigger configured

---

## Stage 6 — Spec Evolution

**Goal:** Harden the worker with spec update handling so plan changes are captured and propagated.

### 6.1 Spec Update Handling

If implementation of a stage reveals necessary changes to the plan:
- Worker updates the spec doc (`docs/planning/<EPIC_KEY>-spec.md`) in place
- Updated spec doc is included in the PR against the feature branch
- Next stage worker branches from the updated feature branch tip, picking up the revised spec automatically

This already works mechanically (workers branch from feature tip and read the spec); Stage 6 is about making it an explicit documented behavior with test coverage, and ensuring the worker's system prompt instructs it to do so.

### Acceptance Criteria

- Worker system prompt explicitly instructs the agent to update the spec doc when the plan changes during implementation
- The PR description notes when the spec was updated and summarizes what changed
- A test or dry-run validates the spec-update path

---

## Stage 7 — Failure Handling & Recovery

**Goal:** Ensure no task gets permanently stuck and lost work is minimized.

### 7.1 Worker Crash / Needs Input

If the worker agent crashes or halts awaiting input:
- Any completed work is committed and pushed to the task branch before exit where possible
- Worker posts a comment on the Jira ticket describing where it stopped and why
- Worker transitions ticket to **Ready** (can retry) or **Needs Input** (human answer required)
- Majordomo will re-queue a **Ready** task on next run; **Needs Input** tasks wait for human intervention

### 7.2 Jenkins Crash (Sweep Job)

If the Jenkins job itself crashes, the worker cannot self-recover. A dedicated sweep job handles this:

- Runs on a regular schedule (e.g. every 4 hours)
- Finds any Implementation Task in **In Progress** for more than **12 hours**
- Transitions those tickets back to **Ready**
- Posts a comment noting the reset and timestamp
- Majordomo will re-queue on next run

### 7.3 Partial / Silent Failure

For failures not caught by the sweep job (e.g. worker completes and opens a PR but the implementation is incorrect):
- CI runs on the PR and surfaces test failures
- Human PR review catches behavioral issues
- Human closes the PR with feedback, resets ticket to **Ready** or **Needs Input** as appropriate

### 7.4 Planning Agent Failure

Same principles apply to the planning agent:
- Crash → commit research doc to task branch, post comment, reset to **Open**
- Needs Input → transition to **Needs Input**, human answers and resets to **Open**
- Sweep job covers Jenkins-level crashes for planning jobs as well (same 12-hour threshold)

### Acceptance Criteria

- Worker system prompt instructs the agent to commit and push any completed work before exiting on crash or blocker
- Worker transitions ticket to **Ready** or **Needs Input** (never leaves it **In Progress**) on any exit that isn't a clean PR open
- A sweep Jenkins job exists, runs on a schedule, finds stale **In Progress** tasks (>12 hours), resets them to **Ready**, and posts a comment
- Planning agent failure handling mirrors worker failure handling

---

## Future Considerations

- **GH Actions migration** — when ready, Jenkinsfile logic moves to workflow YAML; Majordomo, planning agent, worker, and sweep job code remain unchanged
- **Parallel workers** — Majordomo launches N workers; Jenkins parallel builds; `In Progress` transition is the atomic claim
- **WIP commits** — if task failure rates or durations warrant it, introduce WIP commits to task branch mid-task to reduce lost work on Jenkins crash
