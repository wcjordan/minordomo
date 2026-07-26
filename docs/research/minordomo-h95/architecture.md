# Research: minordomo-h95 — Sweep Job False Resets on Weekends

## Bug Summary

When a PR is merged on a weekend, the associated beads task stays `in_progress`
(workers never close their own tasks — Majordomo's Step 4 handles that). The
sweep job runs every 4 hours 7 days a week (`H H/4 * * *`). After 12 hours with
no open PR, it assumes the task is stale/crashed and resets it to `open`.

On Monday, Majordomo Step 4 looks for `in_progress` tasks to detect merged PRs,
but the task is now `open`, so the merged PR is never detected and the task gets
re-queued from scratch.

## Key Files

- `minordomo-sweep/Jenkinsfile` — runs sweep every 4 hours, all days
- `shared/sweep-stale-tasks.sh` — the sweep logic (12h staleness window, checks for open PRs only)
- `majordomo/Jenkinsfile` — cron `H/30 * * * 1-5` (weekdays only)
- `shared/config.yaml` — `weekend_override: true` in schedule config (but irrelevant since Jenkins cron excludes weekends)
- `shared/check-pr-merged.sh` — checks for merged PRs (used by Majordomo Step 4 but NOT by sweep)
- `majordomo/system-prompt.md` — Step 4 (`sync_pr_merge_status`) closes tasks with merged PRs

## Root Cause

The sweep's staleness check (`sweep-stale-tasks.sh`) only checks for open PRs (step 4):

```bash
open_pr_count=$(gh pr list --state open ...)
if [ "${open_pr_count}" -gt 0 ]; then
    continue  # skip — PR is in review
fi
```

It does not check for *merged* PRs. Since the PR was merged (not open), the
task looks stale, and the sweep resets it.

## Alternative Approaches

### Option A: Sweep checks for merged PRs and skips those tasks
- Add a `check-pr-merged.sh` call in the sweep before resetting
- If merged: skip the task (leave in_progress for Majordomo to handle Monday)
- Minimal change; leaves Majordomo's Step 4 as the authoritative closer

### Option B: Sweep closes tasks that have merged PRs
- Add a `check-pr-merged.sh` call in the sweep
- If merged: close the task (takes over Majordomo's Step 4 for this scenario)
- More proactive; doesn't require Majordomo to run to finalize merged tasks
- Risk: sweep becomes responsible for task lifecycle in some cases

### Option C: Extend staleness window for weekend awareness
- Increase threshold from 12h to e.g. 72h, or compute a dynamic window based on day-of-week
- Crude; just delays the false reset rather than eliminating it

### Option D: Run Majordomo on weekends
- Change Jenkins cron from `H/30 * * * 1-5` to `H/30 * * * *`
- `config.yaml` already has `weekend_override: true` in schedule config
- Eliminates root cause entirely; keeps lifecycle management in one place
- Potential cost/noise implications (running Claude on weekends)

## Recommendation

Option A (skip merged tasks in sweep) is the simplest, most targeted fix. Option B
is cleaner if the sweep should also handle lifecycle closure. Option D eliminates
the root cause but may be undesirable for cost reasons.
