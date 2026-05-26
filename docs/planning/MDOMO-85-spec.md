# MDOMO-85 Implementation Plan: Extract Jira Transition Logic

## Summary

Create `shared/jira-transition.sh` to DRY up the repeated GET-find-POST Jira transition pattern, then update all three agent system prompts to use it.

---

## Stage 1: Create shared/jira-transition.sh and bats tests

### Description

Write `shared/jira-transition.sh` as a standalone executable script. It takes two positional arguments: `<issue_key>` and `<status_name>`. It reads `JIRA_URL`, `JIRA_EMAIL`, and `JIRA_API_TOKEN` from the environment. It performs the two-step Jira transition (GET transitions list, find entry by `to.name`, POST the transition ID). It exits non-zero with a descriptive error message if the named status is not in the transitions list, if the GET request fails, or if the POST request fails.

Write a bats test file at `test/bats/jira-transition.bats` that mocks `curl` via `$TMP_DIR` on `$PATH` and covers:
- Happy path: status name found, transition posted successfully
- Exit non-zero when target status name is not present in the transitions list
- Exit non-zero when the GET curl call returns a non-zero exit code
- Exit non-zero when JIRA_URL/JIRA_EMAIL/JIRA_API_TOKEN are not set

Run `make test` to verify all tests pass before opening a PR.

### Acceptance Criteria
- `shared/jira-transition.sh` exists, is executable, and passes `shellcheck`
- `test/bats/jira-transition.bats` exists with at least 4 test cases
- `make test` passes with no failures
- Script reads credentials from environment, not positional args

---

## Stage 2: Update agent system prompts to use jira-transition.sh

### Description

Replace every inline Jira transition block (15-line curl+Python) in the three system prompt files with a single call to `shared/jira-transition.sh <issue_key> <status_name>`.

Call sites to update:

1. **`minordomo-plan/system-prompt.md`** — Spec Path Step 5: replace the inline block with:
   ```bash
   shared/jira-transition.sh "${jira_task_id}" "In Review"
   ```

2. **`minordomo-step/system-prompt.md`** — Step 7: replace the inline block with:
   ```bash
   shared/jira-transition.sh "${jira_task_id}" "In Review"
   ```

3. **`majordomo/system-prompt.md`** — Step 4 (Stage tasks): replace `GET transitions … POST` prose with:
   ```bash
   shared/jira-transition.sh "${jira_task_key}" "Done"
   ```

4. **`majordomo/system-prompt.md`** — Step 4 (Plan tasks): replace inline block with:
   ```bash
   shared/jira-transition.sh "${jira_task_key}" "Approved"
   ```

5. **`majordomo/system-prompt.md`** — Step 8 substep 8: replace the GET/POST instructions with:
   ```bash
   shared/jira-transition.sh "${jira_task_key}" "In Progress"
   ```

6. **`majordomo/system-prompt.md`** — Step 9 substep n: replace the GET/POST instructions with:
   ```bash
   shared/jira-transition.sh "${EPIC_KEY}" "In Review"
   ```

Update `CLAUDE.md` to add `shared/jira-transition.sh` to the Pipeline Helper Functions section with a brief usage note.

Run `make test` to verify the prompt validation script passes before opening a PR.

### Acceptance Criteria
- All six inline transition blocks replaced with `shared/jira-transition.sh` one-liners
- No inline `TRANSITIONS=\$(curl …)` + python3 blocks remain in any system prompt
- `CLAUDE.md` documents `shared/jira-transition.sh`
- `make test` passes with no failures
