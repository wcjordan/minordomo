# Implementation Plan: Failure handling — planning agent crash and needs-input recovery

Epic: minordomo-zci
GH Issue: https://github.com/wcjordan/minordomo/issues/212

---

## Stage 1: Create `shared/post-jira-comment.sh` with bats tests

### Description
Add a new shared script that posts a comment to a Jira issue via REST API.
This is the atomic building block used by Stage 2's error-exit flow and Stage 3's
questions-path Jira notification.

The script takes two positional arguments: `jira_issue_key` and `comment_body`.

Implementation:
- Follow the `set -euo pipefail` + argument guard pattern used in `shared/jira-transition.sh`
- Guard on required environment variables: `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`
- Run:
  ```bash
  curl -sf -X POST -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
      -H "Content-Type: application/json" \
      "${JIRA_URL}/rest/api/3/issue/${jira_issue_key}/comment" \
      -d "{\"body\": {\"type\": \"doc\", \"version\": 1, \"content\": [{\"type\": \"paragraph\", \"content\": [{\"type\": \"text\", \"text\": \"${comment_body}\"}]}]}}"
  ```
- Exit non-zero with a descriptive message if the `curl` command fails
- Write `test/bats/post-jira-comment.bats` with:
  - Happy path: curl succeeds
  - Missing argument guard (fewer than 2 args)
  - Missing env var guard (JIRA_URL/JIRA_EMAIL/JIRA_API_TOKEN unset)
  - curl failure (non-zero exit → script exits non-zero with error message)
- Reference: `test/bats/apply-needs-input.bats` for the bats mocking pattern

### Acceptance Criteria
- `shared/post-jira-comment.sh MDOMO-133 "Planning stopped at step 3"` POSTs a comment to the Jira issue
- Exits non-zero with a descriptive error if the `curl` command fails
- Exits non-zero (without calling `curl`) if called with fewer than 2 arguments
- Exits non-zero (without calling `curl`) if any required env var is unset
- `make test` passes with the new bats test file

---

## Stage 2: Create `shared/planner-error-exit.sh` with bats tests

### Description
Add a new shared script that encapsulates the deterministic 3-step sequence needed on
any planning agent error exit (crash or unrecoverable blocker):

1. Get the Jira epic key via `shared/get-epic-key.sh "$BEADS_TASK_ID" "$REPO"` (read line 3: JIRA_EPIC_KEY)
2. Post a Jira comment via `shared/post-jira-comment.sh "$JIRA_EPIC_KEY" "$comment_body"` (best-effort — log failure and continue)
3. Reset beads task to open via `shared/beads-write.sh update "$BEADS_TASK_ID" --status open`

Usage: `shared/planner-error-exit.sh <beads_task_id> <repo> <comment_body>`

Best-effort vs required:
- Step 1 (get-epic-key): if it fails, log the error, skip step 2, and still attempt step 3
- Step 2 (post-jira-comment): if it fails, log the error and continue to step 3
- Step 3 (beads reset): required — if it fails, log the error and exit non-zero

Jira comment body shape: the `<comment_body>` argument should describe what the planner was
doing when it stopped and why. Callers are responsible for constructing a meaningful message.

Write `test/bats/planner-error-exit.bats` with:
- Happy path: all 3 steps succeed
- `get-epic-key.sh` fails: Jira comment skipped, beads reset still called, exits 0
- `post-jira-comment.sh` fails: logged, beads reset still called, exits 0
- `beads-write.sh` fails: exits non-zero
- Missing argument guard (fewer than 3 args)
- Reference `test/bats/apply-needs-input.bats` for mocking patterns

### Acceptance Criteria
- `shared/planner-error-exit.sh` exists and encapsulates get-epic-key + post Jira comment + beads reset
- Jira comment step is best-effort (failure is logged, beads reset still runs)
- get-epic-key failure skips Jira comment but still attempts beads reset
- Beads reset failure causes non-zero exit
- `make test` passes with the new bats test file

---

## Stage 3: Update planning agent system prompt — connect error/crash and needs-input recovery

### Description
Update `minordomo-plan/system-prompt.md` so no exit path leaves the beads task `in_progress`.

**Part A — Error/Crash Exit Flow (new section)**

Add a clearly labelled "Error/Crash Exit Flow" section near the Questions Path defining
the 2-step pre-exit procedure for any unrecoverable error:

1. **Commit and push partial work**: run `git status --porcelain`; if output is non-empty, run:
   ```bash
   git add docs/research/$EPIC_KEY/ docs/planning/$EPIC_KEY-spec.md 2>/dev/null || true
   git commit -m "[partial] <brief description of what was attempted>"
   git push
   ```
   If working tree is clean, skip this step. If commit or push fails, log the failure
   and continue to step 2 (do not let a git failure prevent the beads reset).

2. **Call `shared/planner-error-exit.sh "$BEADS_TASK_ID" "minordomo" "<message>"`** where
   `<message>` describes what the planner was doing and why it stopped. The message should
   include: which step failed, a brief description of the error, and the GH issue number.

After these two steps, emit the run log with `status: "failure"` and exit 1.

Update the generic preamble ("On any unrecoverable error, record it in errors, emit the log,
and exit 1") to reference the Error/Crash Exit Flow.

**Part B — Questions Path (Needs Input) updates**

The existing Questions Path calls `apply-needs-input.sh` which handles GH label, GH comment,
and beads reset. Two additions:

1. **Move the commit step before `apply-needs-input.sh`** (currently the commit is step 2,
   after the apply-needs-input call). The reordered Questions Path should be:
   a. Commit and push any current research/spec work (as in Part A step 1)
   b. Call `shared/apply-needs-input.sh minordomo "${gh_issue_number}" "${BEADS_TASK_ID}" "<questions>"` (existing)
   c. **(New)** Post Jira comment (best-effort):
      ```bash
      { read -r _STORY; read -r _GH_NUM; read -r JIRA_EPIC_KEY; } \
          < <(shared/get-epic-key.sh "${BEADS_TASK_ID}" "minordomo") && \
          shared/post-jira-comment.sh "${JIRA_EPIC_KEY}" \
              "Planning agent has questions before proceeding. See GH issue #${gh_issue_number} for the full question list." \
          || echo "Warning: could not post Jira comment (non-fatal)"
      ```
   d. Emit run log and exit 0

**Part C — Run Log Format**

Update the Run Log Format section to document the new step names that appear in both flows:
- `"commit_partial"` — commit/push partial work (with `"skipped"` status if working tree was clean)
- `"jira_comment"` — Jira comment post step (questions path and error/crash path)
- `"beads_reset"` — beads task reset to open (error/crash path only; questions path uses apply-needs-input)

Add a short example showing what the run log looks like when the Error/Crash Exit Flow fires:
```json
{
  "run_id": "...",
  "beads_task_id": "...",
  "status": "failure",
  "steps": [
    {"step": "read_planning_task", "status": "ok"},
    {"step": "read_gh_issue", "status": "ok"},
    {"step": "load_research", "status": "ok", "files_found": 0},
    {"step": "research", "status": "error", "message": "..."},
    {"step": "commit_partial", "status": "ok"},
    {"step": "jira_comment", "status": "ok"},
    {"step": "beads_reset", "status": "ok"}
  ],
  "errors": ["Research step failed: ..."]
}
```

### Acceptance Criteria
- Planning agent system prompt includes an "Error/Crash Exit Flow" section defining the 2-step pre-exit procedure
- The generic preamble exit instruction references the Error/Crash Exit Flow
- The Questions Path commits partial work as its first step (before apply-needs-input.sh)
- The Questions Path posts a Jira comment (best-effort) after apply-needs-input.sh
- `shared/planner-error-exit.sh` and `shared/post-jira-comment.sh` are referenced in the prompt (must pass `make test` / validate-prompts.py)
- Run log format documents `commit_partial`, `jira_comment`, and `beads_reset` step names
- `make test` passes
