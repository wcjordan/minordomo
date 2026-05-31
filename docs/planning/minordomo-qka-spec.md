# Plan: Autoclosing the Story bead doesn't work for stories / issues from gcp-setup GH repo

## Background

Step 10 (`close_completed_epics`) in `majordomo/system-prompt.md` never closes Story beads because
its `bd list` call omits the `--all` flag. By the time Step 10 runs, all Stage tasks are closed;
`bd list --json` returns only open tasks by default, so the Stage task list is empty and Step 10
skips every Story with reason `"no_impl_tasks"`. The bug affects all repos (not just gcp-setup) —
gcp-setup was simply the first observed case.

The fix is one line: add `--all` to the `bd list --parent` call at Step 10, sub-step c.
Step 9 already uses `--all` for the same purpose; this aligns Step 10 with that pattern.

---

## Stage 1: Fix Step 10 bd list call to include closed Stage tasks

### Description

In `majordomo/system-prompt.md`, update the `bd list` command in Step 10 (sub-step c) from:

```
`bd list --parent "<story_bead_id>" --json`
```

to:

```
`bd list --parent "<story_bead_id>" --all --json`
```

Without `--all`, the default open-only filter returns an empty list once all Stage tasks are
closed, causing Step 10 to skip the Story with reason `"no_impl_tasks"` instead of closing it.

### Acceptance Criteria

- `majordomo/system-prompt.md` Step 10 sub-step c reads: `bd list --parent "<story_bead_id>" --all --json`
- All other `bd list --parent` calls in the same file remain unchanged (they already use the correct flags for their purpose)
- `make test` passes
