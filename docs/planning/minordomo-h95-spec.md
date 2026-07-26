# Implementation Plan: minordomo-h95 — Sweep Job False Resets on Weekends

## Background

The sweep job (`shared/sweep-stale-tasks.sh`) resets in-progress tasks that have been
running 12+ hours with no open PR. When a PR is merged on the weekend, Majordomo
doesn't run (its Jenkins cron is weekdays-only), so the task stays `in_progress`.
After 12 hours, the sweep falsely resets it to `open`.

**Chosen fix (Option A):** Skip tasks in the sweep if they have a merged PR, leaving
them `in_progress` for Majordomo to close on Monday.

---

## Stage 1: Skip merged-PR tasks in the sweep

### Description

Modify `shared/sweep-stale-tasks.sh` to extract the epic key from the
`get-story-key.sh` output (line 1, currently unused), then add a merged-PR check
after the existing open-PR check. If `check-pr-merged.sh` exits 0 (merged PR found),
skip the task by continuing to the next iteration.

Add a bats test to `test/bats/sweep-stale-tasks.bats` that mocks `gh pr list` to
return a merged PR and verifies the task is not reset.

**Exact changes:**

1. `shared/sweep-stale-tasks.sh`:
   - After the line `repo=$(echo "$story_output" | sed -n '3p')`, add:
     `epic_key=$(echo "$story_output" | sed -n '1p')`
   - After Step 4 (open PR check), add Step 4b:
     ```bash
     # Step 4b: Skip tasks that have a merged PR — PR was merged on a weekend
     # while Majordomo was not running; it will close the task on Monday.
     if "${SCRIPT_DIR}/check-pr-merged.sh" "$repo" "$epic_key" "$task_id" 2>/dev/null; then
         echo "Skipping task ${task_id}: merged PR found, Majordomo will close it."
         continue
     fi
     ```

2. `test/bats/sweep-stale-tasks.bats`:
   - Add a test case: "task with merged PR: skipped (not reset)"
   - Mock `gh pr list --state merged` to return `[{"number":42}]` while
     `gh pr list --state open` returns `[]`
   - Assert `bd update` is NOT called (no reset) and summary reads `Swept 0 stale task(s)`

### Acceptance Criteria

- `sweep-stale-tasks.sh` skips tasks when `check-pr-merged.sh` exits 0 (merged PR found)
- `sweep-stale-tasks.sh` still resets tasks when no merged PR is found (no regression)
- `sweep-stale-tasks.sh` still skips tasks when an open PR is found (no regression)
- A new bats test covers the merged-PR skip case and passes
- All existing bats tests continue to pass (`make test` green)
- The task is left `in_progress` when skipped (no `bd update --status open` call)
