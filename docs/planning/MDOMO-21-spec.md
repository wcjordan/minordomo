# MDOMO-21: Merge Base Branch to Feature Branch Routinely

## Overview

Before the worker implements the first implementation task of an epic, merge the configured base branch into the feature branch. This keeps the feature branch current with any commits that landed on the base branch after planning occurred, preventing conflicts from accumulating silently until the final feature → base PR.

The merge is triggered by detecting that the current task is the first implementation task of its Epic (lowest Jira rank among siblings). It happens in `setup-workspace.sh` worker mode, after checking out the feature branch but before creating the task branch — so the task branch automatically includes the merged commits.

---

## Stage 1: Add base-branch merge to setup-workspace.sh

### Description

Modify `shared/setup-workspace.sh` to detect when the worker is running the first implementation task of an Epic and, if so, merge `origin/${BASE_BRANCH}` into the feature branch before creating the task branch.

**Detection logic:**
- Query the Jira search API for all implementation siblings of the current Epic (`parent = ${EPIC_KEY} AND issuetype = Task AND summary !~ "^Plan:"`, fields: `customfield_10019`).
- Sort results by `customfield_10019` ascending (lexicographic; same ordering used by Majordomo's promotion step).
- If `sorted_issues[0]['key'] == JIRA_TASK_ID`, this is the first implementation task.

**Merge logic (in worker mode, only when first task):**
```bash
git fetch origin "${BASE_BRANCH}"
git merge "origin/${BASE_BRANCH}" -m "chore: merge ${BASE_BRANCH} into ${FEATURE_BRANCH} before first implementation stage"
git push origin "${FEATURE_BRANCH}"
```

**Failure behavior:**
- If the Jira siblings API call fails: `curl -f` returns non-zero; `set -euo pipefail` exits the script.
- If the merge has conflicts: `git merge` returns non-zero; script exits with an error.
- If already up to date: `git merge` exits 0 with "Already up to date." — script continues normally.

### Acceptance Criteria

- When the worker runs the first implementation task of an epic, `setup-workspace.sh` fetches and merges `origin/${BASE_BRANCH}` into the feature branch and pushes it before creating the task branch.
- When the worker runs a non-first implementation task, no merge or push to the feature branch occurs.
- If the siblings Jira API call returns no issues, the script exits non-zero with an error message.
- If `git merge` exits non-zero (e.g. conflict), the script exits non-zero.
- Existing planning mode behavior is unchanged.

---

## Stage 2: Add bats tests for the merge behavior

### Description

Add bats test cases in `test/bats/setup-workspace.bats` covering the new first-task merge behavior. This requires:

1. **New fixture** `test/fixtures/jira-siblings-first.json` — search response where `MDOMO-44` is the only (and therefore first) implementation task sibling.

2. **New fixture** `test/fixtures/jira-siblings-not-first.json` — search response where `MDOMO-44` is ranked second (a lower-ranked sibling precedes it).

3. **Updated curl mock** in the test setup: distinguish two URL patterns:
   - URL contains `/rest/api/3/issue/` → return `FIXTURE_JSON` (existing task-response fixture)
   - URL contains `/rest/api/3/search` → return `SIBLINGS_FIXTURE_JSON` (new, configurable per-test)

4. **New test cases:**
   - `worker mode: first task triggers merge of base branch into feature branch` — assert that after sourcing, the feature branch on the remote contains a commit from the base branch merge.
   - `worker mode: non-first task skips base branch merge` — assert that the feature branch HEAD is unchanged.
   - `worker mode: merge that is already up to date succeeds without error` — pre-advance the remote base branch to match feature branch; assert script exits 0.

The existing `worker mode: checks out feature branch and creates fresh task branch` test should continue to pass once the curl mock is updated to handle the new search URL.

### Acceptance Criteria

- `make test` passes with all new and existing test cases.
- The new curl mock correctly routes task-response and search-response URLs to their respective fixtures.
- The "first task" test verifies an actual merge commit landed on the remote feature branch.
- The "non-first task" test verifies the feature branch remote tip is unchanged after sourcing.
- The "already up to date" test verifies the script exits cleanly when there is nothing to merge.
