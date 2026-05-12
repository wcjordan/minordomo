# MDOMO-13: Exclude Done Epics from check_story_completion

## Stage 1: Filter out Done Epics in the check_story_completion JQL query

### Description
In `majordomo/system-prompt.md`, Step 8 ("Open Feature → Main PRs for Completed Stories") currently fetches all Epics using `project = <jira_key> AND issuetype = Epic`, including those already in Done status. For a Done Epic, all implementation tasks are Done and the feature PR has already been merged, so Majordomo would incorrectly attempt to open a duplicate PR. Fix this by adding `AND status != Done` to the JQL, so Done Epics are excluded at query time.

### Acceptance Criteria
- In `majordomo/system-prompt.md`, Step 8 sub-step 1 "Query Epics" JQL reads: `project = <jira_key> AND issuetype = Epic AND status != Done`
- `make test` passes with no errors
