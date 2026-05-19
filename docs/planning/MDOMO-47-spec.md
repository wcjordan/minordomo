# MDOMO-47: Don't ingest or work on any tasks w/ the label `backlog` or `skip`

## Stage 1: Filter backlog/skip issues at ingestion

### Description

Modify Step 3 (Poll GitHub Issues → Create Jira Epics) in `majordomo/system-prompt.md` to skip
any GitHub Issue that carries the `backlog` or `skip` label before attempting to ingest it.

The `gh issue list` call already returns `labels` in its JSON output. Add a check after
filtering by `allowed_gh_users` and before the `jira-epic-created` idempotency check:

```
Skip issues where any label name in `labels[].name` is exactly `backlog` or `skip`.
Log a per-issue skip with reason: `"backlog_or_skip_label"`.
Do not create a Jira Epic, Planning Task, or beads task for these issues.
Do not apply `jira-epic-created` or `beads-ingested` labels to them either.
```

Also update the step log to count these skips alongside already-labelled skips.

### Acceptance Criteria

- Step 3 skips GH Issues with label `backlog`, counting them in the per-step skip log with reason `backlog_or_skip_label`
- Step 3 skips GH Issues with label `skip`, counting them in the per-step skip log with reason `backlog_or_skip_label`
- Step 3 still processes issues that have neither label (regression: `jira-epic-created` idempotency check unchanged)
- No Jira Epic, Planning Task, or beads task is created for skipped issues
- `jira-epic-created` and `beads-ingested` labels are not applied to skipped issues

---

## Stage 2: Skip backlog/skip tasks in planning dispatch and worker dispatch

### Description

Extend the `needs-input` label checks in Steps 5, 6, and 8 of `majordomo/system-prompt.md` to
also bail out when the linked GH Issue carries the `backlog` or `skip` label.

**Step 5 (Evaluate Planning Tasks):** The existing check is:
```bash
gh issue view <issue-number> --repo wcjordan/<repo> --json labels \
  | jq '.labels[].name' | grep -q needs-input && skip_task=true
```
Extend the same pattern to also match `backlog` and `skip`. Log per-task skip with reason
`"backlog_or_skip_label"` (distinct from `"needs_input"`).

**Step 6 (Plan Approval Spinoff):** Step 6 currently has no label check. Add one: after
extracting the GH Issue URL from the Epic's ADF description, fetch the issue's labels and skip
the spinoff for this epic if `backlog` or `skip` is present. Log a per-epic skip with reason
`"backlog_or_skip_label"`. Count toward `epics_skipped` in the step log.

**Step 8 (Launch Worker Agent):** Same extension as Step 5. Log per-task skip with reason
`"backlog_or_skip_label"`.

No changes to Steps 4 or 9 are needed (neither is a dispatch gate).

### Acceptance Criteria

- Step 5 excludes Planning Tasks whose parent Epic's GH Issue has the `backlog` label; logs reason `backlog_or_skip_label`
- Step 5 excludes Planning Tasks whose parent Epic's GH Issue has the `skip` label; logs reason `backlog_or_skip_label`
- Step 5 still excludes tasks with `needs-input` label (regression: existing behavior unchanged)
- Step 6 skips Plan Approval Spinoff for any Epic whose GH Issue has the `backlog` or `skip` label; counts toward `epics_skipped`
- Step 8 excludes Ready Implementation Tasks whose parent Epic's GH Issue has the `backlog` label; logs reason `backlog_or_skip_label`
- Step 8 excludes Ready Implementation Tasks whose parent Epic's GH Issue has the `skip` label; logs reason `backlog_or_skip_label`
- Step 8 still excludes tasks with `needs-input` label (regression: existing behavior unchanged)
- All three steps continue to function normally for issues without these labels
