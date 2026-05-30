# Implementation Plan: Failure handling — worker crash and needs-input recovery

Epic: minordomo-gzq  
GH Issue: https://github.com/wcjordan/minordomo/issues/210

---

## Stage 1: Create `shared/post-gh-issue-comment.sh` with bats tests

### Description
Add a new shared script that posts a comment to a GitHub issue.
This is the atomic building block used by Stage 2's error-exit flow.

The script takes three positional arguments: `gh_issue_number`, `repo`, and `comment_body`.

Implementation:
- Follow the `set -euo pipefail` + argument guard pattern used in `shared/apply-needs-input.sh`
- Run: `gh issue comment "${gh_issue_number}" --repo "wcjordan/${repo}" --body "${comment_body}"`
- Exit non-zero with a descriptive message if the `gh` command fails
- Write `test/bats/post-gh-issue-comment.bats` with: happy path, missing-argument guard,
  and `gh` command failure

### Acceptance Criteria
- `shared/post-gh-issue-comment.sh 210 minordomo "Worker stopped at step 3"` posts a comment to the GH issue
- Exits non-zero with a descriptive error if the `gh` command fails
- Exits non-zero (without calling `gh`) if called with fewer than 3 arguments
- `make test` passes with the new bats test file

---

## Stage 2: Create `shared/worker-error-exit.sh` with bats tests

### Description
Add a new shared script that encapsulates the deterministic 3-step sequence needed on
any worker error exit (non-needs-input path):

1. Get the GH issue number via `shared/get-epic-key.sh "$BEADS_TASK_ID" "$REPO"` (read line 2: GH_ISSUE_NUMBER)
2. Post a GH comment via `shared/post-gh-issue-comment.sh "$GH_ISSUE_NUMBER" "$REPO" "$comment_body"` (best-effort — log failure and continue)
3. Reset beads task to open via `shared/beads-write.sh update "$BEADS_TASK_ID" --status open`

Usage: `shared/worker-error-exit.sh <beads_task_id> <repo> <comment_body>`

Steps 1 and 2 are best-effort: if `get-epic-key.sh` fails, log the error and skip the GH
comment step, then still attempt step 3. If `post-gh-issue-comment.sh` fails, log the error and
continue to step 3. Step 3 (beads reset) is not optional — its failure should be logged as
an error and the script should exit non-zero.

Write `test/bats/worker-error-exit.bats` with:
- Happy path: all 3 steps succeed
- `get-epic-key.sh` fails: GH comment skipped, beads reset still called
- `post-gh-issue-comment.sh` fails: logged, beads reset still called
- `beads-write.sh` fails: exits non-zero
- Missing argument guard

### Acceptance Criteria
- `shared/worker-error-exit.sh` exists and encapsulates get-epic-key + post GH comment + beads reset
- GH comment step is best-effort (failure is logged, beads reset still runs)
- get-epic-key failure also skips GH comment but still attempts beads reset
- Beads reset failure causes non-zero exit
- `make test` passes with the new bats test file

---

## Stage 3: Update worker system prompt — connect error/crash and needs-input recovery

### Description
Update `minordomo-step/system-prompt.md` so no exit path leaves the beads task `in_progress`.

**Part A — Error/crash path (all existing hard `exit 1` points)**

Replace every "log the error and exit 1" instruction in Steps 1–6 and the general run preamble
with a 2-step pre-exit procedure:

1. **Commit and push partial work**: if `git status --porcelain` produces output, run
   `git add -A && git commit -m "[partial] <brief description of what was attempted>" && git push origin task/$BEADS_TASK_ID`.
   If the working tree is clean, skip this step. If the commit or push fails, log the failure
   but continue to step 2 (do not let a git failure prevent the beads reset).
2. **Call `shared/worker-error-exit.sh "$BEADS_TASK_ID" "$REPO" "<message>"`** where
   `<message>` describes what the worker was attempting and why it stopped.

After these two steps, emit the run log with `status: "failure"` and exit 1.

Add a clearly labelled "Error/Crash Exit Flow" section to the system prompt (near the existing
Needs Input Flow) that defines these two steps and explains when to invoke them. Then update
every existing hard-failure instruction to reference this section.

**Part B — Needs Input path (existing Needs Input Flow)**

Prepend one step to the existing Needs Input Flow:

1. **Commit and push partial work** — same procedure as Part A step 1

The existing `get-epic-key.sh` call and `apply-needs-input.sh` call are unchanged.
`apply-needs-input.sh` already posts a comment to the GH issue, so no additional
notification step is needed.

**Part C — Run Log Format**

Update the Run Log Format section to document the new step names that appear in both flows:
- `"commit_partial"` — commit/push partial work (with `"skipped"` status if working tree was clean)
- `"gh_comment"` — GH issue comment post (with `"skipped"` status if GH_ISSUE_NUMBER could not be derived; error/crash path only)
- `"beads_reset"` — beads task reset to open

Add a short example showing what the run log looks like when the Error/Crash Exit Flow fires.

### Acceptance Criteria
- Worker system prompt includes a "Error/Crash Exit Flow" section defining the 2-step pre-exit procedure
- Every hard-failure `exit 1` in Steps 1–6 and the preamble references or invokes the Error/Crash Exit Flow
- The Needs Input Flow commits partial work as its first step
- `shared/worker-error-exit.sh` and `shared/post-gh-issue-comment.sh` are referenced in the prompt (must pass validate-prompts.py)
- Run log format documents `commit_partial`, `gh_comment`, and `beads_reset` step names
- `make test` passes
