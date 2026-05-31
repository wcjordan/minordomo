# Root Cause Analysis: Story Bead Autoclosing Bug

## Bug Summary

Step 10 (`close_completed_epics`) in `majordomo/system-prompt.md` never closes Story beads because
its `bd list` call omits the `--all` flag.

## Root Cause

Line ~434 of `majordomo/system-prompt.md` (Step 10, sub-step c):

```bash
bd list --parent "<story_bead_id>" --json
```

`bd list --json` without `--status` or `--all` returns only **open** tasks. By the time Step 10
runs, all Stage tasks are closed (they were closed by `sync_pr_merge_status` / the worker pipeline).
The returned array is empty, so Step 10 skips with reason `"no_impl_tasks"` and never reaches the
PR-merged check or the beads close call.

Step 9 (`check_story_completion`) correctly uses `--all`:

```bash
bd list --parent "<story_bead_id>" --all --json
```

Step 10 is missing that flag.

## Verification

```bash
# Returns 0 items (all children closed):
bd list --parent minordomo-low --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"
# => 0

# Returns 4 items with --all:
bd list --parent minordomo-low --all --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"
# => 4
```

## Why "gcp-setup"

`minordomo-low` (a gcp-setup story) was the first observed case. The bug affects every Story bead
in every repo equally — it's not gcp-setup specific. The GH issue title reflects the observed
symptom, not a repo-specific code path.

## Fix

In `majordomo/system-prompt.md`, Step 10, sub-step c: add `--all` to the `bd list` command.

**Before:**
```
`bd list --parent "<story_bead_id>" --json`
```

**After:**
```
`bd list --parent "<story_bead_id>" --all --json`
```

## Scope

- One-line change in `majordomo/system-prompt.md`
- No shell scripts affected (the bug lives in the prompt, not in a helper script)
- No bats test needed (prompt logic is not unit-tested at the shell level)

## Flow Trace (Post-Fix)

After the fix, Step 10 for a completed gcp-setup epic (`minordomo-low` as example):

1. `list-story-beads.sh` returns open Story beads (if `minordomo-low` were still open)
2. `get-story-key.sh minordomo-low` → EPIC_KEY=`minordomo-low`, GH_ISSUE_NUMBER=16, REPO=`gcp-setup`
3. `bd list --parent minordomo-low --all --json` → returns 4 children (all closed Stage tasks)
4. All Stage tasks are `"closed"` → passes the completeness check
5. `check-epic-pr-merged.sh gcp-setup main minordomo-low` → returns PR #21 (merged)
6. `beads-write.sh close minordomo-low` → Story bead closed ✓
