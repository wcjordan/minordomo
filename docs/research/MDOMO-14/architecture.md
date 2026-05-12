# Research: MDOMO-14 — Update Jira based on human PR interactions

## Feature Summary

When a human merges a GitHub PR:
- Planning task PR (spec doc → feature branch) → transition Jira ticket to **Approved**
- Implementation task PR (task branch → feature branch) → transition Jira ticket to **Done**

Currently these transitions are manual; this feature automates them.

---

## Current Gap

Majordomo runs Steps 1-8 on a schedule. After a planning or worker agent opens a PR and
transitions the task to **In Review**, the system waits for a human to merge the PR.
Currently, the human must also **manually** transition the Jira ticket after merging.

The new step will detect merged PRs and perform these transitions automatically.

---

## Implementation Approach

Add a new **Step 4** ("Sync PR Merge Status to Jira") between the current Step 3
(Poll GH Issues) and Step 4 (Evaluate Planning Tasks). The new step:

1. Queries Jira for all Tasks in **"In Review"** status across all configured projects  
   JQL: `project in (<jira_keys>) AND issuetype = Task AND status = "In Review"`  
   Fields: `summary`, `status`, `parent`

2. For each "In Review" task:
   - Derives `repo` from the jira_key prefix (via config.yaml lookup)
   - Reads `parent.key` to get the Epic key → constructs base branch `feature/<EPIC_KEY>`
   - Constructs head branch: `task/<TASK_KEY>`
   - Checks for merged PR:
     ```bash
     gh pr list --repo wcjordan/<repo> \
       --base feature/<EPIC_KEY> \
       --head task/<TASK_KEY> \
       --state merged --json number
     ```
   - If result array is non-empty → PR was merged
     - Planning task (summary starts with "Plan:") → transition to **Approved**
     - Implementation task → transition to **Done**
   - Transition via Jira REST:
     ```bash
     GET  ${JIRA_URL}/rest/api/3/issue/<TASK_KEY>/transitions   # find id where to.name matches
     POST ${JIRA_URL}/rest/api/3/issue/<TASK_KEY>/transitions   # {"transition":{"id":"<id>"}}
     ```
   - Errors are per-task (log and continue; do not abort the step)

Existing Steps 4-8 are renumbered to Steps 5-9.

---

## Affected Files

| File | Change |
|---|---|
| `majordomo/system-prompt.md` | Add new Step 4, renumber Steps 4-8 → 5-9, update run log format |
| `docs/WORKFLOWS.md` | Update "Human actions required" + Done status rows to note automation |
| `docs/GETTING_AROUND.md` | Update "Steps 1–8" reference to "Steps 1–9" |

---

## Key Patterns (from existing code)

**Jira JQL search (Step 6 pattern):**
```bash
GET ${JIRA_URL}/rest/api/3/search?jql=<encoded_jql>&fields=summary,status,parent,customfield_10019&maxResults=100
```

**Jira transition (Step 6 pattern):**
```bash
GET  ${JIRA_URL}/rest/api/3/issue/<KEY>/transitions
POST ${JIRA_URL}/rest/api/3/issue/<KEY>/transitions  body: {"transition":{"id":"<id>"}}
```

**GitHub PR check (Step 8 pattern):**
```bash
gh pr list --repo wcjordan/<repo> --base <base> --head <head> --state open --json number
```
Extended for merged: `--state merged`

---

## Status Flows (target)

### Planning Task
```
In Review → Approved   (when spec PR merged — now automated)
```

### Implementation Task
```
In Review → Done       (when impl PR merged — now automated)
```

---

## Run Log Entry (new step)

```json
{
  "step": "sync_pr_merge_status",
  "status": "ok",
  "tasks_checked": 3,
  "tasks_transitioned": 2
}
```
