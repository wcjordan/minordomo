# Implementation Plan: MDOMO-112

Resolve the Story bead and Jira epic when the final PR for an Epic is merged to main.

## Stage 1: Detect merged feature PRs and close completed epics

### Description

Add a new Step 10 to Majordomo's `system-prompt.md` that runs after the existing Step 9. It detects when the feature→main PR for a completed epic has been merged by a human, then closes the Story bead and transitions the Jira Epic to "Done".

Also fix a race condition in Step 9: when a feature→main PR is merged, Step 9 currently checks only for open PRs, so on the next Majordomo run it would attempt to open a duplicate PR. Update Step 9's PR-existence check (step 2g) to use `--state all` instead of `--state open`, preventing duplicate PR creation.

**Changes to `majordomo/system-prompt.md`:**

1. **Fix Step 9 step 2g** — change `--state open` to `--state all` in the PR-existence guard so Majordomo never opens a second PR from `feature/<EPIC_KEY>` to `<base_branch>` once one already exists (open or merged).

2. **Add Step 10: Close Completed Epics After Feature PR Merges**

   Initialize: `epics_checked = 0`, `epics_closed = 0`, `epics_skipped = 0`, `epic_errors = []`

   a. Query open Story beads:
      ```bash
      bd list --json | python3 -c "
      import json, sys
      tasks = json.load(sys.stdin)
      print(json.dumps([t for t in tasks if t.get('title', '').startswith('Story:')]))
      "
      ```

   b. For each Story bead:
      - Increment `epics_checked`
      - Derive `repo` from beads task ID prefix (longest-match against config repos)
      - Fetch Stage children: `bd list --parent "<story_bead_id>" --json` — filter to titles starting with `"Stage"`
      - Skip if no Stage children (reason: `"no_impl_tasks"`)
      - Skip if any Stage child status is not `"closed"` (reason: `"impl_tasks_not_done"`)
      - Derive EPIC_KEY using `shared/get-epic-key.sh`:
        ```bash
        { read -r EPIC_KEY; read -r GH_ISSUE_NUMBER; } < <(shared/get-epic-key.sh "<story_bead_id>" "<repo>")
        ```
        On failure: append per-epic error to `epic_errors`, increment `epics_skipped`, continue
      - Check for a merged feature→main PR:
        ```bash
        gh pr list \
          --repo wcjordan/<repo> \
          --base <base_branch> \
          --head feature/<EPIC_KEY> \
          --state merged \
          --json number
        ```
        If the array is empty: increment `epics_skipped` (reason: `"pr_not_yet_merged"`) and continue
      - Close the Story bead:
        ```bash
        shared/beads-write.sh close "<story_bead_id>"
        ```
        On error: append per-epic error, increment `epics_skipped`, continue
      - Transition the Jira Epic to "Done":
        ```bash
        shared/jira-transition.sh "${EPIC_KEY}" "Done"
        ```
        On error: append per-epic error (do not abort; Story bead already closed)
      - Increment `epics_closed`

   c. Log step result:
      ```json
      {"step": "close_completed_epics", "status": "ok", "epics_checked": N, "epics_closed": N, "epics_skipped": N}
      ```
      Append any entries from `epic_errors` to the top-level `errors` array.

3. **Update run log format** — add the new step's log entry to the example in the Run Log Format section:
   ```json
   {"step": "close_completed_epics", "status": "ok", "epics_checked": 0, "epics_closed": 0, "epics_skipped": 0}
   ```

### Acceptance Criteria
- Step 9's PR-existence guard uses `--state all` so no duplicate PRs are ever opened for the same epic
- New Step 10 is present in `majordomo/system-prompt.md` after Step 9
- Step 10 queries open Story beads and skips those with incomplete Stage children
- Step 10 detects a merged feature→main PR via `gh pr list --state merged`
- When a merged PR is found, Step 10 closes the Story bead via `shared/beads-write.sh close`
- When a merged PR is found, Step 10 transitions the Jira Epic to "Done" via `shared/jira-transition.sh`
- Step 10 logs `close_completed_epics` with `epics_checked`, `epics_closed`, `epics_skipped` counts
- The run log format example includes the new step
- `make test` passes (shellcheck, bats, prompt validation)
