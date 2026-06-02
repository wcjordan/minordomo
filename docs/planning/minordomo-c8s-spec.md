# Implementation Plan: minordomo-c8s

**Issue:** [GH #290](https://github.com/wcjordan/minordomo/issues/290) — A PR to main should not be opened until the PR for the final stage has been merged

## Background

Majordomo Step 9 opens a feature→main PR when all Stage beads tasks are `closed`. The owner observed a case where a feature→main PR was opened while the final stage PR (task→feature) was still unmerged. The fix has two parts: clarify the beads query so it unambiguously covers in_progress tasks, and add a GH PR safety check as defense-in-depth.

---

## Stage 1: Clarify Majordomo Step 9 beads completeness check

### Description

The current Step 9c instruction uses `bd list --all` to fetch Stage children. While `--all` does include `in_progress` tasks (empirically verified), this is not evident from the flag description ("Show all issues including closed"). If the AI executor interprets `--all` as "open + closed only," in-progress Stage tasks would be invisible to the check, and the feature→main PR could be opened while a final-stage worker is still running.

Fix: replace `--all` with the explicit `--status=open,in_progress,closed` in the Step 9c instruction so that the AI's intent is unambiguous. Also add a callout before Step 9e explicitly naming the three statuses that indicate incomplete work (`open`, `in_progress`, `blocked`).

Changes are solely in `majordomo/system-prompt.md`.

### Acceptance Criteria

- Step 9c in `majordomo/system-prompt.md` no longer uses `--all`; it uses `--status=open,in_progress,closed` (or an equivalent explicit enumeration)
- A note near Step 9e makes clear that any Stage task with status `open`, `in_progress`, or `blocked` is considered not-done and causes the epic to be skipped
- `make test` passes

---

## Stage 2: Add GH open-task-PR guard in Majordomo Step 9

### Description

Add a new shared script `shared/check-open-task-prs.sh` and wire it into Majordomo Step 9 as a defense-in-depth check. Before opening the feature→main PR (but after the existing beads completeness check), Majordomo calls this script to confirm that no open `task/` PRs are targeting the feature branch. If any exist, the epic is skipped with reason `"task_prs_unmerged"`.

This catches edge cases where beads state is inconsistent (e.g., a Stage task was closed manually but its PR is still open) and directly implements the owner's requested Option A.

**Script contract:**
- Usage: `check-open-task-prs.sh <repo> <epic_key>`
- Exits 0 with output (head branch name of first match) if any open task PRs target `feature/<epic_key>` — caller should skip
- Exits 1 with no output if no open task PRs exist — caller may proceed
- Exits 2 on wrong argument count

**Implementation detail:** `gh pr list` does not support wildcard `--head`, so the script lists all open PRs against `feature/<epic_key>` and filters `headRefName` values starting with `task/` in Python (same pattern as `check-pr-merged.sh`).

**Step 9 placement:** the new sub-step runs after the existing "Skip — incomplete" beads check (9e) and before "Skip — PR exists" (9f). Skip reason: `"task_prs_unmerged"`.

### Acceptance Criteria

- `shared/check-open-task-prs.sh` exists and is executable
- Script exits 0 (print head branch name) when `gh pr list` returns at least one open PR with `headRefName` starting with `task/`
- Script exits 1 when no such PRs exist
- Script exits 2 when called with wrong argument count
- `test/bats/check-open-task-prs.bats` covers: open task PR present → exits 0; no open task PRs → exits 1; non-task open PRs → exits 1; wrong arg count → exits 2
- `majordomo/system-prompt.md` Step 9 calls `shared/check-open-task-prs.sh` between the beads completeness check and the "PR exists" check, skipping with reason `"task_prs_unmerged"` when it exits 0
- `make test` passes
