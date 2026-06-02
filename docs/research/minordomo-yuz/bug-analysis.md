# Bug Analysis: Missing `needs-input` label on error exits

## Issue

When agent runs fail and need human input, they post a comment to the GH issue but do not apply the `needs-input` label. This means Majordomo's label-based skip logic doesn't fire and the issue may be re-queued instead of waiting for human resolution.

## Root Cause

Two scripts handle the error exit paths, and neither applies the `needs-input` label:

### `shared/worker-error-exit.sh`
Steps:
1. Get GH issue number via `get-story-key.sh` (best-effort)
2. Post GH comment via `post-gh-issue-comment.sh` (best-effort)
3. Reset beads task to open (required)

**Missing**: `gh issue edit ... --add-label needs-input` before step 2.

### `shared/planner-error-exit.sh`
Steps:
1. Post GH comment directly via `gh issue comment` (best-effort when issue number provided)
2. Reset beads task to open (required)

**Missing**: `gh issue edit ... --add-label needs-input` before step 1 (when issue number is available).

## Contrast with `apply-needs-input.sh`

`apply-needs-input.sh` (used on the "Questions Path") correctly does all 3 steps:
1. `gh issue edit ... --add-label needs-input` (exits 1 on failure)
2. `gh issue comment ...` (exits 1 on failure)
3. `beads-write.sh update ... --status open` (exits 1 on failure)

The error exit scripts treat GH operations as best-effort, but they're still missing the label step entirely.

## Fix

Add `gh issue edit "${GH_ISSUE_NUMBER}" --repo "wcjordan/${repo}" --add-label needs-input` (best-effort, logged on failure) to both:
- `worker-error-exit.sh` — before calling `post-gh-issue-comment.sh`
- `planner-error-exit.sh` — inside the `if [ -n "${gh_issue_number}" ]` block, before the comment

## Tests to Update

- `test/bats/worker-error-exit.bats`: verify `gh issue edit --add-label needs-input` is called, and that label failure is best-effort (beads reset still runs)
- `test/bats/planner-error-exit.bats`: verify `gh issue edit --add-label needs-input` is called when issue number provided; verify it's skipped when issue number is empty
