# Implementation Plan: Failure handling — worker crash and needs-input recovery

Epic: minordomo-gzq  
GH Issue: https://github.com/wcjordan/minordomo/issues/210

---

## Stage 1: Create `shared/post-jira-comment.sh` with bats tests

### Description
Add a new shared script that posts a comment to a Jira issue via the Jira REST API.
This is the atomic building block needed by Stages 2 and 3.

The script takes two positional arguments (`jira_issue_key` and `comment_body`) and reads
`JIRA_URL`, `JIRA_EMAIL`, and `JIRA_API_TOKEN` from the environment.

Implementation:
- Follow the `set -euo pipefail` + `curl -sf` + error message pattern used in `shared/jira-transition.sh`
- POST to `${JIRA_URL}/rest/api/3/issue/${jira_issue_key}/comment` with ADF body:
  `{"body": {"type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "<comment_body>"}]}]}}`
- Exit non-zero with a descriptive message if credentials are missing or the POST fails
- Write `test/bats/post-jira-comment.bats` with: happy path, missing-argument guard,
  missing-env-var cases (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN), and curl failure

### Acceptance Criteria
- `shared/post-jira-comment.sh MDOMO-131 "Worker stopped at step 3"` posts a comment to the Jira issue
- Exits non-zero with a descriptive error if JIRA_URL, JIRA_EMAIL, or JIRA_API_TOKEN are unset
- Exits non-zero with a descriptive error if the curl call fails
- Exits non-zero (without calling curl) if called with fewer than 2 arguments
- `make test` passes with the new bats test file

---

## Stage 2: Create `shared/worker-error-exit.sh` with bats tests

### Description
Add a new shared script that encapsulates the deterministic 3-step sequence needed on
any worker error exit (non-needs-input path):

1. Get the Jira Epic key via `shared/get-epic-key.sh "$BEADS_TASK_ID" "$REPO"`
2. Post a Jira comment via `shared/post-jira-comment.sh "$JIRA_EPIC_KEY" "$comment_body"` (best-effort — log failure and continue)
3. Reset beads task to open via `shared/beads-write.sh update "$BEADS_TASK_ID" --status open`

Usage: `shared/worker-error-exit.sh <beads_task_id> <repo> <jira_comment_body>`

Steps 1 and 2 are best-effort: if `get-epic-key.sh` fails, log the error and skip the Jira
comment step, then still attempt step 3. If `post-jira-comment.sh` fails, log the error and
continue to step 3. Step 3 (beads reset) is not optional — its failure should be logged as
an error and the script should exit non-zero.

Write `test/bats/worker-error-exit.bats` with:
- Happy path: all 3 steps succeed
- `get-epic-key.sh` fails: Jira comment skipped, beads reset still called
- `post-jira-comment.sh` fails: logged, beads reset still called
- `beads-write.sh` fails: exits non-zero
- Missing argument guard

### Acceptance Criteria
- `shared/worker-error-exit.sh` exists and encapsulates get-epic-key + post Jira comment + beads reset
- Jira comment step is best-effort (failure is logged, beads reset still runs)
- get-epic-key failure also skips Jira comment but still attempts beads reset
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

Prepend two steps to the existing Needs Input Flow:

1. **Commit and push partial work** — same procedure as Part A step 1
2. **Capture JIRA_EPIC_KEY** — update the existing `get-epic-key.sh` call to read all three
   output lines:
   ```bash
   { read -r _EPIC_KEY; read -r GH_ISSUE_NUMBER; read -r JIRA_EPIC_KEY; } < <(shared/get-epic-key.sh "${BEADS_TASK_ID}" "$REPO")
   ```
   The existing step that calls `apply-needs-input.sh` is unchanged.

Append one step after the existing `apply-needs-input.sh` call:

3. **Post Jira comment** — call `shared/post-jira-comment.sh "$JIRA_EPIC_KEY" "<message>"`
   with the same explanation as the GH comment. If this call fails, log it but continue
   (non-fatal, because `apply-needs-input.sh` already reset the beads task).

**Part C — Run Log Format**

Update the Run Log Format section to document the new step names that appear in both flows:
- `"commit_partial"` — commit/push partial work (with `"skipped"` status if working tree was clean)
- `"jira_comment"` — Jira comment post (with `"skipped"` status if JIRA_EPIC_KEY could not be derived)
- `"beads_reset"` — beads task reset to open

Add a short example showing what the run log looks like when the Error/Crash Exit Flow fires.

### Acceptance Criteria
- Worker system prompt includes a "Error/Crash Exit Flow" section defining the 2-step pre-exit procedure
- Every hard-failure `exit 1` in Steps 1–6 and the preamble references or invokes the Error/Crash Exit Flow
- The Needs Input Flow commits partial work as its first step
- The Needs Input Flow captures `JIRA_EPIC_KEY` from `get-epic-key.sh` line 3
- The Needs Input Flow posts a Jira comment after `apply-needs-input.sh` (best-effort)
- `shared/worker-error-exit.sh` and `shared/post-jira-comment.sh` are referenced in the prompt (must pass validate-prompts.py)
- Run log format documents `commit_partial`, `jira_comment`, and `beads_reset` step names
- `make test` passes
