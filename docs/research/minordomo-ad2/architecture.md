# Research: Stale Task Sweep Architecture

## Overview

This sweep job provides a backstop for Jenkins-level crashes where the worker or planning agent
container dies before it can self-report — ensuring no task stays permanently orphaned in `in_progress`.

## Beads Task State

In-progress beads tasks have a `started_at` field (ISO 8601 timestamp in `bd list --status=in_progress --json`).
Compare this against `now - 12h` to detect stale tasks.

All in_progress tasks should be swept — both Stage N tasks (worker) and Plan: tasks (planning agent),
per the acceptance criteria.

## Resetting a Task to Open

`shared/beads-write.sh update <id> --status open`

This pattern is already used in `shared/apply-needs-input.sh`.

## Posting a Comment

For both Stage tasks and Plan tasks, use `shared/get-epic-key.sh <beads_task_id> <repo>` to derive:
- Line 1: Story bead ID
- Line 2: GH_ISSUE_NUMBER
- Line 3: JIRA_EPIC_KEY

Then post to the GH issue with `gh issue comment <number> --repo wcjordan/<repo> --body "..."`.

## Deriving Repo from Beads Task ID

Longest-match against config repos, same as `shared/setup-workspace.sh`.
The sweep script embeds this logic via Python (same pattern as setup-workspace.sh).

## Jenkinsfile Pattern

New directory: `minordomo-sweep/Jenkinsfile`
- Cron trigger: `H */4 * * *` (every 4 hours using Jenkins hash distribution)
- Uses same `minordomo-image` container as majordomo
- Requires the same credentials: `GH_APP`, `JIRA_ACCT`, `JENKINS_API_KEY` (for beads dolt sync)
- Runs `shared/sweep-stale-tasks.sh`

## Test Pattern

Bats tests in `test/bats/sweep-stale-tasks.bats`. Mock `bd`, `gh`, and `shared/beads-write.sh` in `$MOCKS`.
The sweep script is self-contained; no startup sequence (bootstrap.sh) is needed since the
Jenkinsfile handles that separately.
