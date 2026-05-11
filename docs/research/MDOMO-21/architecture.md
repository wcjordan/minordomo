# MDOMO-21: Merge Base Branch to Feature Branch — Research Notes

## Feature Goal

Merge the configured base branch into the feature branch before implementing the first implementation task of an epic, in case it has gotten out of date since planning occurred.

## Key Files

- `shared/setup-workspace.sh` — workspace setup script; already makes Jira API calls and handles git branching
- `minordomo-step/system-prompt.md` — worker agent prompt; runs after setup-workspace.sh
- `test/bats/setup-workspace.bats` — bats tests for setup-workspace.sh
- `test/fixtures/jira-task-response.json` — fixture for Jira task API response

## Current Worker Branch Flow (in setup-workspace.sh)

1. Derive REPO from Jira project key via config.yaml
2. Call Jira REST API to get parent Epic key
3. Set FEATURE_BRANCH = feature/${EPIC_KEY}
4. Run `gh auth setup-git` and clone repo
5. Check out feature branch (assumes it exists in worker mode)
6. Create fresh task branch from feature branch tip: `git checkout -b task/${JIRA_TASK_ID}`

## Where to Add the Merge

The merge must happen **between steps 5 and 6** above — after checking out the feature branch but before creating the task branch. This ensures the task branch includes the merged base-branch commits.

## How to Detect First Implementation Task

Query Jira for all implementation task siblings under the same Epic:
```
GET ${JIRA_URL}/rest/api/3/search?jql=parent=${EPIC_KEY}%20AND%20issuetype=Task%20AND%20summary%20!~%20%22%5EPlan%3A%22&fields=customfield_10019&maxResults=100
```

Sort results by `customfield_10019` (Jira rank) ascending — lexicographic sort, lower = earlier stage.

If `sorted_issues[0]['key'] == JIRA_TASK_ID`, this is the first implementation task.

Note: The Jira rank field (`customfield_10019`) is already used by Majordomo's Step 6 for the same "sibling ordering" purpose.

## Merge Command Sequence

```bash
git fetch origin "${BASE_BRANCH}"
git merge "origin/${BASE_BRANCH}" -m "chore: merge ${BASE_BRANCH} into ${FEATURE_BRANCH} before first implementation stage"
git push origin "${FEATURE_BRANCH}"
```

- If already up to date: `git merge` exits 0 with "Already up to date." message — safe to continue
- If conflict: `git merge` exits 1 — script should fail loudly (set -euo pipefail handles this)
- Push is needed so the feature branch remote is updated before the task branch PR targets it

## Test Fixture Strategy

The current `curl` mock in `setup-workspace.bats` returns the same fixture for all curl calls. The new code adds a second Jira API call (the siblings search). The mock needs to differentiate URLs:

- URL contains `/rest/api/3/issue/` → return `jira-task-response.json` (task with parent Epic)
- URL contains `/rest/api/3/search` → return `jira-siblings-response.json` (search results with sibling tasks)

The new fixture `test/fixtures/jira-siblings-response.json` needs to cover:
- First task: `{"issues": [{"key": "MDOMO-44", "fields": {"customfield_10019": "0|aaaaaa:"}}]}`
- Non-first task: same but with an additional lower-ranked sibling before MDOMO-44

## Edge Cases

1. **No siblings found**: Should not happen (the current task must be a sibling), but handle by exiting with error
2. **Merge already up to date**: git exits 0, safe to continue
3. **Merge conflict**: git exits 1, set -euo pipefail causes script to exit with error
4. **API call failure**: curl -f flag causes non-zero exit on HTTP error, script exits

## Impact

- Planning mode: unchanged
- Worker mode: adds one Jira API call + optional git merge+push before task branch creation
- The merge commit is on the feature branch — task branch PR to feature branch will not include it
- The eventual feature → base PR will include the merge commit
