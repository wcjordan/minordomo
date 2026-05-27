# Epic Lifecycle Research — MDOMO-112

## Goal
Resolve (close) the Story bead and transition the Jira Epic to "Done" when the final PR for an Epic is merged to main.

## Current State

### Step 9 (existing): Open Feature → Main PRs for Completed Stories
- Triggered when: all Stage children of a Story bead are closed AND no open PR exists
- Actions: opens `feature/<EPIC_KEY>` → `<base_branch>` PR, transitions Jira Epic to "In Review"
- After this step: PR is open, awaiting human merge

### Missing: Post-merge closure
After the human merges the feature→main PR, nothing currently:
- Closes the Story bead
- Transitions the Jira Epic from "In Review" to "Done"

## Implementation Design

### New Step 10: Close Completed Epics After Feature PR Merges

**Detection logic:**
1. Query open Story beads: `bd list --json` filtered to `title.startswith("Story:")`
2. For each Story bead: fetch Stage children (`bd list --parent <id> --json`)
3. Skip if no Stage children (no impl tasks)
4. Skip if any Stage child is not closed (impl not done)
5. Derive EPIC_KEY and repo via `shared/get-epic-key.sh`
6. Check for merged feature→main PR:
   ```bash
   gh pr list --repo wcjordan/<repo> --base <base_branch> --head feature/<EPIC_KEY> --state merged --json number
   ```
7. If merged PR found:
   - Close Story bead: `shared/beads-write.sh close "<story_bead_id>"`
   - Transition Jira Epic to "Done": `shared/jira-transition.sh "${EPIC_KEY}" "Done"`

### Key References
- `shared/beads-write.sh`: wrapper for beads mutations (handles dolt pull/push)
- `shared/jira-transition.sh`: transitions a Jira issue to named status
- `shared/get-epic-key.sh <beads_task_id> <repo>`: prints EPIC_KEY (line 1) and GH_ISSUE_NUMBER (line 2)
- `base_branch`: read from `shared/config.yaml` (value: `main`)

### Edge Cases
- Story bead already closed: naturally excluded by `bd list --json` (returns open only)
- No Stage children: skip with reason `"no_impl_tasks"`
- Stage children not all closed: skip with reason `"impl_tasks_not_done"`
- No merged PR: skip (PR still open or not yet created)
- EPIC_KEY derivation fails: log per-epic error, continue

### Log Format for New Step
```json
{"step": "close_completed_epics", "status": "ok", "epics_checked": N, "epics_closed": N, "epics_skipped": N}
```

## File to Modify
`majordomo/system-prompt.md` — add Step 10 after Step 9, update run log example format
