# Implementation Plan: All Implementation Steps in a Single Jenkins Run

GH Issue: https://github.com/wcjordan/minordomo/issues/420

## Summary

Currently each Stage requires a separate Jenkins job and a Majordomo cycle to unblock. This plan
implements a `minordomo-steps` multi-stage job that runs all implementation stages for an epic
in a single Jenkins run. Each stage creates its own PR; successive stage branches are stacked on
the previous one so each PR shows only that stage's diff when reviewed in order.

---

## Stage 1: Backward-compatible infrastructure prep

### Description

Lay the groundwork that the new multi-step job will depend on, in a fully backward-compatible
way so the existing `minordomo-step` job continues to work unchanged.

Two changes:

**1. Worker system prompt: `TARGET_BRANCH` env var support**

In `minordomo-step/system-prompt.md`, the `gh pr create` call uses `--base "$FEATURE_BRANCH"`.
Change it to `--base "${TARGET_BRANCH:-$FEATURE_BRANCH}"`. When `TARGET_BRANCH` is not set
(existing `minordomo-step` job), behaviour is identical. When `TARGET_BRANCH` is set by the
multi-step Jenkinsfile, the PR targets the previous stage's task branch instead.

**2. `shared/check-pr-merged.sh`: drop the `--base` filter**

Currently the script filters `--base "feature/${epic_key}"`. For stacked PRs, Stage 2+ have a
previous task branch as base, not the feature branch, so the filter would miss them.

Remove the `--base` flag from the `gh pr list` call. The `--head "task/${beads_task_id}"` filter
is sufficient — head branches are unique per task. All callers (Majordomo Step 4, Step 6, and
`sweep-stale-tasks.sh`) work correctly with the broader query.

### Acceptance Criteria

- `shared/check-pr-merged.sh` no longer passes `--base` to `gh pr list`
- `minordomo-step/system-prompt.md` uses `${TARGET_BRANCH:-$FEATURE_BRANCH}` as the PR base in
  the `gh pr create` call
- `make test` passes (shellcheck, bats, prompt validation)

---

## Stage 2: `minordomo-steps` Jenkinsfile and supporting scripts

### Description

Implement the new multi-step job. Two deliverables:

**1. `shared/list-story-stage-tasks.sh`**

New helper script: given a Story bead ID, outputs all Stage task IDs for that story one per
line, sorted ascending by stage number extracted from the title (`Stage N: ...`). Includes all
statuses (open, blocked, in_progress, closed) so the full ordered list is available regardless
of where in the lifecycle each task is.

**2. `minordomo-steps/Jenkinsfile`**

New Jenkins job modelled on `minordomo-step/Jenkinsfile` + `shared/agent-pipeline.Jenkinsfile`,
with these differences:

- Takes `BEADS_TASK_ID` as parameter (the first — or resumption — stage task ID)
- Uses non-interactive mode only (no `INTERACTIVE_MODE` parameter)
- Runs a loop in a single worker pod that:
  1. Calls `source shared/bootstrap.sh worker` for the first task (normal clone + branch setup)
  2. Derives `STORY_BEAD_ID` from the task via `bd show`
  3. Gets the ordered stage list: `"$SHARED/list-story-stage-tasks.sh" "$STORY_BEAD_ID"`
  4. Finds the starting index (the given `BEADS_TASK_ID` in the list)
  5. For the first task: exports `BEADS_TASK_ID` and `TARGET_BRANCH="$FEATURE_BRANCH"`, runs
     `claude -p "$(cat ../../minordomo-step/system-prompt.md)" --output-format json`
  6. For each subsequent stage task:
     a. `git fetch origin "task/${PREV_TASK_ID}"` (fetch the previous stage's pushed branch)
     b. `git checkout -b "task/${NEXT_TASK_ID}" "origin/task/${PREV_TASK_ID}"`
     c. `"$SHARED/beads-write.sh" update "$NEXT_TASK_ID" --claim`
     d. Export `BEADS_TASK_ID=$NEXT_TASK_ID` and `TARGET_BRANCH="task/${PREV_TASK_ID}"`
     e. Run `claude -p ...`
  7. If any Claude run exits non-zero, stop the loop and exit non-zero
  8. After the loop: `cd ..` back to workspace root, `bd dolt pull && bd dolt push`
  9. Run beads token-reporting and PR Discord notification (same as existing jobs)
- Followed by the same "Beads Status" pod stage as in `agent-pipeline.Jenkinsfile`

The loop does **not** close any task after PR creation. Tasks remain `in_progress` and are
closed by Majordomo's existing Step 4 when each PR is merged — the existing invariant is preserved.

**Run log output**: each Claude run writes its JSON output to `/tmp/claude-output-${TASK_ID}.json`.
After the loop, all outputs are merged for the token-usage report and PR Discord notification.

### Acceptance Criteria

- `minordomo-steps/Jenkinsfile` exists and passes `make test` (shellcheck on any new .sh files)
- `shared/list-story-stage-tasks.sh` exists, is executable, and correctly outputs stage task IDs
  in ascending stage-number order
- Running the multi-step job for a 2-stage epic results in both stages running in sequence, each
  creating a PR (Stage 2's PR targets Stage 1's task branch)
- If Stage 1 fails (Claude exits non-zero), the loop stops; Stage 2 is not claimed or run
- `make test` passes

---

## Stage 3: Wire Majordomo and update docs

### Description

Switch Majordomo from triggering `minordomo-step` to `minordomo-steps`, and update docs.

**1. `majordomo/system-prompt.md` Step 8**

In Step 8 (Launch Worker Agent), change:
```bash
shared/jenkins-trigger.sh minordomo-step "<beads_impl_id>"
```
to:
```bash
shared/jenkins-trigger.sh minordomo-steps "<beads_impl_id>"
```

The `minordomo-step` job is kept as-is for manual single-step runs but is no longer triggered
by Majordomo automatically.

**2. `docs/GETTING_AROUND.md`**

Add `minordomo-steps/` to the Repository Structure table:
```
├── minordomo-steps/
│   └── Jenkinsfile  — Multi-step worker job; runs all stages for an epic in one run
```
Update the System Capabilities table: change "Worker agents" row to note that implementation
runs multiple stages in a single Jenkins run.

**3. `docs/WORKFLOWS.md`**

Update the Branching Model section to show the new stacked task branch structure:
```
<base_branch>
└── feature/story-bead-id
    ├── task/story-bead-id.0     (planning; PR → feature)
    ├── task/story-bead-id.1     (stage 1; PR → feature)
    │   └── task/story-bead-id.2 (stage 2; PR → task/story-bead-id.1)
    │       └── task/story-bead-id.3 (stage 3; PR → task/story-bead-id.2)
```

Update the Stage status table to note that `in_progress` now means "claimed and actively
implementing OR awaiting PR review (multi-step runs)".

Update the Prioritization (Step 8) section to note `minordomo-steps` replaces `minordomo-step`.

### Acceptance Criteria

- `majordomo/system-prompt.md` triggers `minordomo-steps` in Step 8
- `docs/GETTING_AROUND.md` documents the new job
- `docs/WORKFLOWS.md` shows the updated stacked branching model
- `make test` passes (prompt validation checks Step 8)
