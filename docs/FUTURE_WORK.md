# Future Work

Planned capabilities not yet implemented. File a GH Issue for any of these to have the system plan and implement it autonomously.

---

## Usage Limits & Scheduling

**Goal:** Respect Claude usage limits and run only at appropriate times.

### Usage Check

Before launching any worker, Majordomo:
- Makes an OAuth request to `https://api.anthropic.com/api/oauth/usage` to retrieve weekly usage
  - Reference implementation: [`claude_quota.py`](https://github.com/slopware/claude-quota/blob/main/claude_quota.py)
  - **Note:** This endpoint is unofficial and undocumented; verify it works before relying on it and handle gracefully if it changes
- Checks weekly usage against a configurable threshold (default: **50%**)
- If usage ≥ threshold → logs decision, exits without launching a worker

### Time-of-Day Gating

Majordomo enforces a configurable schedule:

Config in `shared/config.yaml`:
```yaml
schedule:
  allowed_days: [Mon, Tue, Wed, Thu, Fri]
  allowed_hours: ["00:00-08:00", "18:00-23:59"]
  weekend_override: false
```

If outside the allowed window → log decision, exit 0 without launching any agents.

### Jenkins Scheduling

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

## Spec Evolution

**Goal:** Harden the worker with spec update handling so plan changes are captured and propagated.

### Spec Update Handling

If implementation of a stage reveals necessary changes to the plan:
- Worker updates the spec doc (`docs/planning/<EPIC_KEY>-spec.md`) in place
- Updated spec doc is included in the PR against the feature branch
- Next stage worker branches from the updated feature branch tip, picking up the revised spec automatically
- Note: the spec doc is present on the feature branch throughout implementation and is deleted by Majordomo (Step 9) before the feature→main PR is opened — spec evolution happens before that point

This already works mechanically (workers branch from feature tip and read the spec); this work is about making it an explicit documented behavior with test coverage, and ensuring the worker's system prompt instructs it to do so.

### Acceptance Criteria

- Worker system prompt explicitly instructs the agent to update the spec doc when the plan changes during implementation
- The PR description notes when the spec was updated and summarizes what changed
- A test or dry-run validates the spec-update path

---

## Failure Handling & Recovery

**Goal:** Ensure no task gets permanently stuck and lost work is minimized.

### Worker Crash / Needs Input

If the worker agent crashes or halts awaiting input:
- Any completed work is committed and pushed to the task branch before exit where possible
- Worker posts a comment on the Jira ticket describing where it stopped and why
- Worker transitions ticket to **Ready** (can retry) or **Needs Input** (human answer required)
- Majordomo will re-queue a **Ready** task on next run; **Needs Input** tasks wait for human intervention

### Jenkins Crash (Sweep Job)

If the Jenkins job itself crashes, the worker cannot self-recover. A dedicated sweep job handles this:

- Runs on a regular schedule (e.g. every 4 hours)
- Finds any beads Stage task in **in_progress** status for more than **12 hours**
- Resets those tasks to **open**
- Posts a comment noting the reset and timestamp
- Majordomo will re-queue on next run

### Partial / Silent Failure

For failures not caught by the sweep job (e.g. worker completes and opens a PR but the implementation is incorrect):
- CI runs on the PR and surfaces test failures
- Human PR review catches behavioral issues
- Human closes the PR with feedback, resets ticket to **Ready** or **Needs Input** as appropriate

### Planning Agent Failure

Same principles apply to the planning agent:
- Crash → commit research doc to task branch, post comment, reset to **Open**
- Needs Input → transition to **Needs Input**, human answers and resets to **Open**
- Sweep job covers Jenkins-level crashes for planning jobs as well (same 12-hour threshold)

### Acceptance Criteria

- Worker system prompt instructs the agent to commit and push any completed work before exiting on crash or blocker
- Worker resets beads task to **open** or applies needs-input (never leaves it **in_progress**) on any exit that isn't a clean PR open
- A sweep Jenkins job exists, runs on a schedule, finds stale **In Progress** tasks (>12 hours), resets them to **Ready**, and posts a comment
- Planning agent failure handling mirrors worker failure handling

---

## Other Considerations

- **GH Actions migration** — when ready, Jenkinsfile logic moves to workflow YAML; Majordomo, planning agent, worker, and sweep job code remain unchanged
- **Parallel workers** — Majordomo launches N workers; Jenkins parallel builds; `beads-write.sh update --claim` is the atomic claim operation
- **WIP commits** — if task failure rates or durations warrant it, introduce WIP commits to task branch mid-task to reduce lost work on Jenkins crash
