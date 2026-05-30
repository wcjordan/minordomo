# Implementation Plan: Failure handling — planning agent crash and needs-input recovery

Epic: minordomo-zci
GH Issue: https://github.com/wcjordan/minordomo/issues/212

---

## Stage 1: Create `shared/planner-error-exit.sh` with bats tests

### Description
Add a new shared script that encapsulates the deterministic steps needed on any planning
agent error exit (crash or unrecoverable blocker).

Usage: `shared/planner-error-exit.sh <beads_task_id> <repo> <gh_issue_number> <comment_body>`

The script takes four positional arguments: `beads_task_id`, `repo`, `gh_issue_number`, and
`comment_body`. The caller is responsible for supplying the GH issue number — the planning agent
always reads it early in its run, so it should be available at any exit point.

Steps (in order):

1. **Post a GH comment (best-effort)**:
   ```bash
   gh issue comment "${gh_issue_number}" --repo "wcjordan/${repo}" --body "${comment_body}"
   ```
   If this fails, log the error and continue to step 2.

2. **Reset beads task to open (required)**:
   ```bash
   shared/beads-write.sh update "${beads_task_id}" --status open
   ```
   If this fails, log the error and exit non-zero.

Implementation:
- Follow the `set -euo pipefail` + argument guard pattern used in `shared/apply-needs-input.sh`
- Guard: exit 2 if called with fewer than 4 arguments
- Step 1 is best-effort: use `||` to catch failure, log to stderr, and continue
- Step 2 is required: use `||` to catch failure, log to stderr, and `exit 1`
- Reference: `shared/apply-needs-input.sh` for the pattern

Write `test/bats/planner-error-exit.bats` with:
- Happy path: both steps succeed
- GH comment fails: error is logged, beads reset still runs, exits 0
- `beads-write.sh` fails: exits non-zero
- Missing argument guard (fewer than 4 args)
- Reference `test/bats/apply-needs-input.bats` for mocking patterns

### Acceptance Criteria
- `shared/planner-error-exit.sh` exists and encapsulates GH comment + beads reset
- GH comment step is best-effort (failure is logged, beads reset still runs)
- Beads reset failure causes non-zero exit
- `make test` passes with the new bats test file

---

## Stage 2: Update planning agent system prompt — connect error/crash and needs-input recovery

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

2. **Call `shared/planner-error-exit.sh "$BEADS_TASK_ID" "minordomo" "$GH_ISSUE_NUMBER" "<message>"`**
   where `<message>` describes what the planner was doing and why it stopped. The message should
   include: which step failed, a brief description of the error, and the GH issue number.
   If the GH issue number is not yet known (crash before `read_gh_issue` step), pass `""` for
   `gh_issue_number` — the GH comment will be skipped, but the beads reset will still run.

After these two steps, emit the run log with `status: "failure"` and exit 1.

Update the generic preamble ("On any unrecoverable error, record it in errors, emit the log,
and exit 1") to reference the Error/Crash Exit Flow.

**Part B — Questions Path (Needs Input) updates**

The existing Questions Path calls `apply-needs-input.sh` which handles GH label, GH comment,
and beads reset. One addition: **move the commit step before `apply-needs-input.sh`** (currently
the commit is step 2, after the apply-needs-input call). The reordered Questions Path should be:

   a. Commit and push any current research/spec work (as in Part A step 1)
   b. Call `shared/apply-needs-input.sh minordomo "${gh_issue_number}" "${BEADS_TASK_ID}" "<questions>"` (existing)
   c. Emit run log and exit 0

**Part C — Run Log Format**

Update the Run Log Format section to document the new step names that appear in both flows:
- `"commit_partial"` — commit/push partial work (with `"skipped"` status if working tree was clean)
- `"gh_comment"` — GH issue comment post step (error/crash path only; questions path uses apply-needs-input)
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
    {"step": "gh_comment", "status": "ok"},
    {"step": "beads_reset", "status": "ok"}
  ],
  "errors": ["Research step failed: ..."]
}
```

### Acceptance Criteria
- Planning agent system prompt includes an "Error/Crash Exit Flow" section defining the 2-step pre-exit procedure
- The generic preamble exit instruction references the Error/Crash Exit Flow
- The Questions Path commits partial work as its first step (before apply-needs-input.sh)
- `shared/planner-error-exit.sh` is referenced in the prompt (must pass `make test` / validate-prompts.py)
- Run log format documents `commit_partial`, `gh_comment`, and `beads_reset` step names
- `make test` passes
