# Research: All Implementation Steps in a Single Jenkins Run

## Problem Statement

Currently each Stage runs in a separate Jenkins job triggered by Majordomo. Each Majordomo cycle
(every 30 min) triggers one stage, waits for PR merge (human action), then on the next run detects
the merge, closes the beads task, and triggers the next stage. This is slow.

The user wants: all implementation stages for an epic run in a single Jenkins job, each creating
its own PR stacked on the previous one.

## Current Pipeline Flow

1. Majordomo Step 8 triggers `minordomo-step` with a single BEADS_TASK_ID
2. Worker clones repo, creates task branch from feature branch tip, implements stage, opens PR
3. Human reviews and merges PR
4. Next Majordomo run detects merge via `check-pr-merged.sh`, closes beads task
5. Stage N+1 is now unblocked (dependency on Stage N satisfied), Majordomo triggers it next run
6. Repeat

## Desired Flow

1. Majordomo Step 8 triggers `minordomo-steps` with the first stage's BEADS_TASK_ID
2. Multi-step job: all stages run in a single Jenkins run
   - Stage 1: task branch based on feature branch, PR → feature branch
   - Stage 2: task branch based on Stage 1's task branch, PR → Stage 1's task branch
   - Stage N: task branch based on Stage N-1's task branch, PR → Stage N-1's task branch
3. Human reviews and merges PRs in order (each PR diff shows only that stage's changes)
4. Majordomo's existing Step 4 handles closing tasks after each PR merges (unchanged)

## Critical Invariant: Don't Close Tasks Early

The existing pipeline assumes `task closed ⟺ PR merged`. Closing tasks before PR merge would:
- Trigger Step 9 to open feature→main PR prematurely (even though task-branch PRs are open,
  Step 9 has `check-open-task-prs.sh` as a safeguard, but the state would be misleading)
- Break the semantic meaning of beads task status

**Solution**: Collect all stage tasks upfront using `bd list --parent <story_id>`, ordered by
stage number from the title. Run them in dependency order without closing any task early.
Subsequent stages are claimed via `beads-write.sh update --claim` even when they're "blocked"
in beads (the dependency check is Majordomo's orchestration concern, not beads enforcement).

## Key Components to Modify

### 1. `shared/check-pr-merged.sh`
Currently filters `--base "feature/${epic_key}"`. For stacked PRs, Stage 2+ has a previous
task branch as base, not the feature branch. Must drop the `--base` filter.

Callers:
- Majordomo Step 4 (sync PR merge status): finds merged stage PRs
- Majordomo Step 6 (plan approval): finds merged plan PRs (plan PRs still target feature branch)
- `shared/sweep-stale-tasks.sh`: skips tasks with merged PRs

Dropping `--base` is safe — head branches are unique per task (`task/<beads-id>`).

### 2. `minordomo-step/system-prompt.md`
Worker uses hardcoded `--base "$FEATURE_BRANCH"` for `gh pr create`. Needs to respect
`TARGET_BRANCH` env var when set:
```bash
gh pr create --base "${TARGET_BRANCH:-$FEATURE_BRANCH}"
```
Backward compatible: existing `minordomo-step` job doesn't set `TARGET_BRANCH`, so it
continues targeting the feature branch.

### 3. New `shared/list-story-stage-tasks.sh`
Helper that returns all stage task IDs for a story, one per line, sorted by stage number.
```bash
bd list --parent "$STORY_BEAD_ID" --status=open,blocked,in_progress,closed --json
# filter to Stage tasks, sort by stage number extracted from title
```

### 4. New `minordomo-steps/Jenkinsfile`
New Jenkins job that:
1. Runs `source shared/bootstrap.sh worker` for the first task (normal setup)
2. Collects all stage tasks for the story
3. For each subsequent stage: creates task branch from previous stage's branch, claims task,
   exports BEADS_TASK_ID and TARGET_BRANCH, runs `claude -p`
4. Runs beads dolt sync after all stages complete

### 5. `majordomo/system-prompt.md` Step 8
Change `jenkins-trigger.sh minordomo-step` to `jenkins-trigger.sh minordomo-steps`.

## Branching Model (New)

```
feature/EPIC_KEY
└── task/stage-bead-id.1   (Stage 1; PR → feature/EPIC_KEY)
    └── task/stage-bead-id.2   (Stage 2; PR → task/stage-bead-id.1)
        └── task/stage-bead-id.3   (Stage 3; PR → task/stage-bead-id.2)
```

When reviewing: Stage 1 PR diff shows only Stage 1 changes. Stage 2 PR diff shows only
Stage 2 changes (since base is Stage 1's branch). After Stage 1 merges, Stage 2's diff
to feature branch auto-shows only Stage 2 changes.

## Notes

- `bd update --claim` on a blocked task: beads doesn't enforce dependency checks on claim.
  Majordomo's Step 8 does the check, but the multi-step Jenkinsfile bypasses Step 8 for
  stages 2+. Direct `bd update --claim` succeeds.
- CWD after bootstrap: bootstrap.sh cd's into the target repo. Subsequent git commands
  run from that repo. Beads commands use BEADS_DIR env var (set by bootstrap to workspace
  root's .beads) so they work from any directory.
- The SHARED env var is set by bootstrap to workspace_root/shared/ before the cd, so
  script paths like $SHARED/list-story-stage-tasks.sh work from anywhere.
