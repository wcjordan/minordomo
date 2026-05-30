# Implementation Plan: Failure handling — Jenkins crash sweep job for stale in-progress tasks

## Background

When a Jenkins container dies before the agent can self-report, beads tasks may be permanently
orphaned in `in_progress`. This spec creates a dedicated sweep job that runs on a schedule, detects
stale in-progress tasks, resets them to open, and posts a comment so the cause is visible.

---

## Stage 1: Core sweep script and unit tests

### Description

Write `shared/sweep-stale-tasks.sh` — a standalone script (no Claude invocation) that:

1. Lists all in_progress beads tasks via `bd list --status=in_progress --json`.
2. Filters to tasks where `started_at` is more than 12 hours in the past (use Python to parse ISO 8601 and compare against `datetime.utcnow()`).
3. Derives the repo for each stale task by longest-match against config repos in `shared/config.yaml` (same Python pattern as `shared/setup-workspace.sh`).
4. For each stale task:
   a. Try to derive the GH issue number via `shared/get-epic-key.sh <task_id> <repo>` and post a comment with `gh issue comment`.
      - If `get-epic-key.sh` or `gh issue comment` fails: log the per-task error to stderr and continue — do not block the reset.
   b. Reset the task to open via `shared/beads-write.sh update <task_id> --status open`.
      - If the reset fails: log the per-task error and continue to the next task.
5. Print a summary line to stdout: `Swept N stale task(s) to open (M comment errors).`
6. Exit 0 even if some tasks encountered errors (partial success is better than aborting the sweep).

The comment body for step 4a should be:
> Sweep job reset this task to `open` at `<UTC timestamp>`. It had been `in_progress` for more than 12 hours — likely due to a Jenkins container crash. Majordomo will re-queue it on the next run.

Write bats unit tests in `test/bats/sweep-stale-tasks.bats`. Test cases must cover:
- Happy path: one stale task is reset and commented
- Multiple stale tasks: all are swept
- Non-stale task is not reset (under 12 hours)
- `get-epic-key.sh` failure: task is still reset (comment failure does not block reset)
- `gh issue comment` failure: task is still reset
- `bd list` returns empty: exits 0 with `Swept 0 stale task(s)` message

Ensure `test/bats/sweep-stale-tasks.bats` passes `shellcheck` without warnings (add the new script to `test/shellcheck.sh` if needed — check whether `test/shellcheck.sh` auto-discovers `shared/*.sh`).

### Acceptance Criteria

- `shared/sweep-stale-tasks.sh` exists and passes shellcheck
- Script correctly identifies in_progress tasks older than 12 hours and skips those newer than 12 hours
- Script resets each stale task to open via `shared/beads-write.sh update <id> --status open`
- Script attempts to post a GH issue comment before resetting; a comment failure does not prevent the reset
- Script exits 0 when all tasks are swept (including partial comment failures)
- `test/bats/sweep-stale-tasks.bats` exists and all tests pass
- `make test` passes

---

## Stage 2: Jenkins sweep job and documentation

### Description

Create `minordomo-sweep/Jenkinsfile` — a Jenkins pipeline that runs `shared/sweep-stale-tasks.sh`
on a cron schedule. Do **not** invoke `shared/bootstrap.sh` (that clones repos and requires a mode);
instead, follow the majordomo pattern: `source shared/setup-env.sh`, then `gh auth setup-git`, then
`bd bootstrap && bd dolt pull`, then call the sweep script, then `bd dolt push`.

**Jenkinsfile structure:**
- Uses `pipeline { ... }` declarative syntax (not scripted)
- `agent none` at pipeline level; single stage uses a Kubernetes pod with the `minordomo-image`
- Cron trigger: `H H/4 * * *` (every 4 hours, hash-distributed)
- `disableConcurrentBuilds()` option (sweep must not overlap itself)
- Timeout: 15 minutes
- Credentials: `GH_APP` (for gh CLI) and `JIRA_ACCT` (required by `setup-env.sh`)
- `post { failure { notifyFailure() } }`

**Note for Stage 2 acceptance criteria:** The `minordomo-sweep` Jenkins pipeline job must be manually
created in the Jenkins UI pointing to `minordomo-sweep/Jenkinsfile` in this repo. Add a comment in the
Jenkinsfile header documenting this requirement.

Update documentation:
- `docs/GETTING_AROUND.md` — add `minordomo-sweep/` to the repository structure tree and add a row to the "System Capabilities" table: `| Stale task sweep | Resets tasks orphaned by Jenkins crashes back to open on a 4-hour schedule |`
- `docs/agent-workflow-spec.md` — add "Stale Task Sweep" to the "Current Capabilities" section describing the sweep job, its 12-hour threshold, and that it covers both worker and planning agent tasks

### Acceptance Criteria

- `minordomo-sweep/Jenkinsfile` exists with a cron trigger (`H H/4 * * *`), `disableConcurrentBuilds()`, and a 15-minute timeout
- Jenkinsfile uses the majordomo credential pattern (`GH_APP`, `JIRA_ACCT`) — no `CLAUDE_CODE_OAUTH_TOKEN`, no `JENKINS_API_KEY`
- Jenkinsfile sources `setup-env.sh` and runs `bd bootstrap && bd dolt pull` before calling `shared/sweep-stale-tasks.sh`
- Jenkinsfile header comment notes that a Jenkins pipeline job must be manually created in the UI
- `docs/GETTING_AROUND.md` documents the new directory and capability
- `docs/agent-workflow-spec.md` documents the stale task sweep capability
- `make test` passes
