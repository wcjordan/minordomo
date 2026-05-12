# MDOMO-13 Research Notes: Exclude Done Epics from check_story_completion

## Problem

In `majordomo/system-prompt.md`, **Step 8 (check_story_completion / "Open Feature → Main PRs for Completed Stories")** fetches all Epics using the JQL:

```
project = <jira_key> AND issuetype = Epic
```

This includes Epics in **Done** status. For a Done Epic:
1. All Implementation Tasks are Done (they were completed when the epic closed)
2. No open PR exists (it was merged already)

So Majordomo would attempt to open a *new* feature→base PR for an already-merged feature, which would either fail (if the branch is gone) or create a duplicate PR. This is the bug MDOMO-13 addresses.

## Fix Location

**File:** `majordomo/system-prompt.md`  
**Section:** Step 8 — "Open Feature → Main PRs for Completed Stories", sub-step 1 "Query Epics"  
**Current JQL:** `project = <jira_key> AND issuetype = Epic`  
**Fixed JQL:** `project = <jira_key> AND issuetype = Epic AND status != Done`

## Why JQL-level exclusion (not a skip check)

Excluding at the JQL level means Done Epics are never fetched, so:
- `epics_checked` counter accurately reflects only relevant epics
- No new skip reason needed in the log
- Avoids wasted REST API calls to fetch child tasks for Done Epics

## Other Steps Not Affected

- Step 6 (promote_tasks): queries for `Open` impl tasks — no Done Epics involved
- Step 7 (launch_worker): queries for `Ready` impl tasks — no Done Epics involved
- Only Step 8 queries Epics directly, so only one JQL needs changing

## Test Suite Impact

`make test` runs:
1. `shellcheck` — shell scripts only, unaffected
2. `bats` unit tests — tests `setup-env.sh`, `setup-claude.sh`, `setup-workspace.sh` — unaffected
3. `validate-prompts.py` — checks file paths and Jenkins job names in backtick spans — unaffected

No new tests are needed; the change is a one-line JQL modification in a markdown prompt file.
