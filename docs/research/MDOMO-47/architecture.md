# MDOMO-47 Research: Skip `backlog` / `skip` labeled issues

## Feature Request

GitHub Issue #76: "Don't ingest or work on any tasks w/ the label `backlog` or `skip`"

Use case: allow users to add ideas to the repo as GH Issues without Majordomo picking them up.

## Touch Points in `majordomo/system-prompt.md`

All changes are confined to `majordomo/system-prompt.md`.

### Step 3 — Poll GitHub Issues (ingestion gate)

`gh issue list` already returns `labels` in its JSON. Adding a filter before the `jira-epic-created`
check is the natural place to skip issues with `backlog` or `skip` labels. No new API calls needed.

### Step 5 — Evaluate Planning Tasks (planning dispatch gate)

Already extracts the GH Issue URL and checks for the `needs-input` label. Extend the same
`gh issue view ... --json labels` call to also test for `backlog` / `skip`.

### Step 6 — Plan Approval Spinoff

Creates implementation tasks from approved plans. If the label is added between plan approval
and spinoff, we should still skip. Add a label check in Step 6 using the same GH Issue URL
extraction pattern already used in Steps 5 and 8.

### Step 8 — Launch Worker Agent (worker dispatch gate)

Already extracts the GH Issue URL and checks for `needs-input`. Same extension as Step 5.

## What NOT to change

- Step 4 (sync_pr_merge_status): only transitions already-merged PRs; label state doesn't block merges
- Step 9 (open feature→main PRs): only acts on fully-done epics; not a dispatch gate

## Test suite impact

`test/validate-prompts.py` only validates static file paths and Jenkins job names in prompt files.
It does not check label logic. No new tests need to be written; the existing suite will pass
after editing the prompt.

## Label check pattern (reuse existing)

Steps 5 and 8 already use:
```bash
gh issue view <issue-number> --repo wcjordan/<repo> --json labels \
  | jq '.labels[].name' | grep -q needs-input && skip_task=true
```

Extend to:
```bash
gh issue view <issue-number> --repo wcjordan/<repo> --json labels \
  | jq -r '.labels[].name' | grep -qE '^(needs-input|backlog|skip)$' && skip_task=true
```

Or add a separate parallel check for `backlog`/`skip` with its own skip reason.
