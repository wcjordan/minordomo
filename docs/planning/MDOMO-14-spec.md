# Implementation Plan: MDOMO-14 — Update Jira based on human PR interactions

## Overview

Automate Jira ticket transitions when humans merge GitHub PRs.
Currently, humans must manually transition Jira tickets after merging:
- Planning task spec PR merged → human manually sets ticket to **Approved**
- Implementation task PR merged → human manually sets ticket to **Done**

This plan adds a new Majordomo step that detects merged PRs and performs these transitions automatically.

---

## Stage 1: Add "Sync PR Merge Status" step to Majordomo

### Description

Add a new Step 4 ("Sync PR Merge Status to Jira") to `majordomo/system-prompt.md`, inserting it between the current Step 3 (Poll GH Issues → Create Jira Epics) and the current Step 4 (Evaluate Planning Tasks). The new step queries Jira for all tasks in "In Review" status, checks whether each task's corresponding GitHub PR has been merged using the `gh` CLI, and if so transitions the ticket to the appropriate status: **Approved** for planning tasks (summary starts with "Plan:") or **Done** for implementation tasks. Renumber the existing Steps 4–8 to Steps 5–9 throughout the system prompt. Update the run log format in the same file to include the new step.

Specific implementation details for the new step:

1. Query all tasks in "In Review" across all configured projects:
   - JQL: `project in (<jira_keys>) AND issuetype = Task AND status = "In Review"`
   - Fields: `summary`, `status`, `parent`
   - `GET ${JIRA_URL}/rest/api/3/search?jql=<encoded_jql>&fields=summary,status,parent&maxResults=100`

2. For each "In Review" task:
   - Determine `repo` from the project's config entry (jira_key maps to repo in `majordomo/config.yaml`)
   - Extract Epic key from `fields.parent.key` — if missing, log per-task error and continue
   - Check whether the PR is merged:
     ```bash
     gh pr list --repo wcjordan/<repo> \
       --base feature/<EPIC_KEY> \
       --head task/<TASK_KEY> \
       --state merged --json number
     ```
   - If the JSON array is non-empty → PR was merged; transition the ticket:
     - If `fields.summary` starts with `"Plan:"` → transition to **Approved**
     - Otherwise → transition to **Done**
   - Transition via REST (same pattern as Step 6):
     ```bash
     GET  ${JIRA_URL}/rest/api/3/issue/<TASK_KEY>/transitions   # find id where to.name matches
     POST ${JIRA_URL}/rest/api/3/issue/<TASK_KEY>/transitions   # body: {"transition":{"id":"<id>"}}
     ```
   - On any per-task error: log and continue (do not abort the step)

3. Log the step result:
   ```json
   {"step": "sync_pr_merge_status", "status": "ok", "tasks_checked": N, "tasks_transitioned": N}
   ```

### Acceptance Criteria

- `majordomo/system-prompt.md` contains a "Step 4: Sync PR Merge Status to Jira" section between the current Step 3 and Step 4 content
- The new step's JQL query targets `status = "In Review"` tasks across all configured projects
- The new step uses `gh pr list --state merged` to detect merged PRs
- Planning tasks (summary starts with "Plan:") are transitioned to "Approved" on merged PR
- Implementation tasks are transitioned to "Done" on merged PR
- Existing Steps 4–8 are renumbered to Steps 5–9 throughout the system prompt (all step headings and cross-references updated)
- The run log format in the system prompt includes a `sync_pr_merge_status` entry
- `make test` passes (shellcheck + validate-prompts.py + bats tests all green)

---

## Stage 2: Update documentation to reflect automated PR-merge transitions

### Description

Update `docs/WORKFLOWS.md` and `docs/GETTING_AROUND.md` to reflect that Jira ticket transitions after PR merges are now automated by Majordomo rather than requiring manual human action.

In `docs/WORKFLOWS.md`:
- In the Planning Task status table, update the "Approved" row description from "Human merged the spec PR; Majordomo will spin off Implementation Tasks on next run" to reflect that Majordomo now auto-detects the merge
- In the "Human actions required" subsection, remove or update the line "Approve spec → merge PR → set ticket to **Approved**" — humans still need to merge the PR, but the Jira transition is now automatic
- In the Implementation Task status table, update the "Done" row from "Human merged PR and marked ticket complete" to "Human merged PR; Majordomo auto-transitions on next run"

In `docs/GETTING_AROUND.md`:
- Update the Majordomo entry in the repository structure table comment from "Steps 1–8" to "Steps 1–9"

### Acceptance Criteria

- `docs/WORKFLOWS.md` Planning Task "Approved" row accurately describes the automated transition
- `docs/WORKFLOWS.md` "Human actions required" no longer states humans must manually set the Jira status after merging the spec PR
- `docs/WORKFLOWS.md` Implementation Task "Done" row no longer says "marked ticket complete" as a human action
- `docs/GETTING_AROUND.md` references "Steps 1–9" for the Majordomo system prompt
- `make test` passes
