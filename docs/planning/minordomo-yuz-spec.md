# Implementation Plan: minordomo-yuz

Add the `needs-input` label to GH issues when agent runs fail and post a comment requesting human input.

## Stage 1: Apply `needs-input` label in worker-error-exit.sh and planner-error-exit.sh

### Description

Both `shared/worker-error-exit.sh` and `shared/planner-error-exit.sh` post a comment to the GH issue when an agent run fails but do not apply the `needs-input` label. This means Majordomo's label-based skip logic doesn't fire and the issue may be re-queued instead of waiting for human resolution.

Fix both scripts to apply the `needs-input` label (best-effort, like the comment) when the GH issue number is available, and update their bats tests to verify the label is applied.

**Changes to `shared/worker-error-exit.sh`:**
- In Step 2 (inside the `if [ -n "$GH_ISSUE_NUMBER" ]` block), add a `gh issue edit` call before the existing `post-gh-issue-comment.sh` call:
  ```bash
  gh issue edit "${GH_ISSUE_NUMBER}" --repo "wcjordan/${repo}" --add-label needs-input \
      || echo "ERROR: Failed to apply needs-input label to issue ${GH_ISSUE_NUMBER}" >&2
  ```

**Changes to `shared/planner-error-exit.sh`:**
- Inside the `if [ -n "${gh_issue_number}" ]` block, add a `gh issue edit` call before the existing `gh issue comment` call:
  ```bash
  gh issue edit "${gh_issue_number}" --repo "wcjordan/${repo}" --add-label needs-input \
      || { echo "Failed to apply needs-input label to issue ${gh_issue_number}" >&2; }
  ```

**Changes to `test/bats/worker-error-exit.bats`:**
- Update the `gh` mock in the happy-path test to record which subcommand was called, and assert that `gh issue edit --add-label needs-input` was called.
- Add a test: label application fails (best-effort) — comment and beads reset still run, exits 0.

**Changes to `test/bats/planner-error-exit.bats`:**
- Update the happy-path test's `gh` mock to record subcommands, and assert `gh issue edit --add-label needs-input` was called.
- Update the test for empty `gh_issue_number` to assert neither `gh issue edit` nor `gh issue comment` is called.
- Add a test: label application fails (best-effort) — comment and beads reset still run, exits 0.

### Acceptance Criteria
- `shared/worker-error-exit.sh` calls `gh issue edit ... --add-label needs-input` before posting the comment when GH issue number is available
- `shared/planner-error-exit.sh` calls `gh issue edit ... --add-label needs-input` before posting the comment when GH issue number is non-empty
- Label application failure in both scripts is best-effort: it logs to stderr but does not prevent the comment or beads reset
- When GH issue number is not available (worker: `get-story-key.sh` fails; planner: empty string passed), neither the label nor the comment is applied
- `make test` passes with updated bats tests covering the above behaviors
