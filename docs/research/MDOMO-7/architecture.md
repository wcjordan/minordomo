# MDOMO-7 Research: Architecture & Current State

## What Exists (as of Stage 3 completion)

### File Structure
```
majordomo/
  system-prompt.md       — Majordomo agent instructions (Steps 1-8, Steps 6-8 are stubs)
  config.yaml            — allowed_gh_users, projects (repo+jira_key), base_branch, schedule, usage
  agent-settings.json    — Claude permissions allowlist/denylist + PreBashCommand hook
  requirements.txt       — python dependencies
  jenkins/
    planning-agent/
      Jenkinsfile        — parameterized pipeline (JIRA_TASK_ID param)
      system-prompt.md   — planning agent instructions
    worker/
      Jenkinsfile        — parameterized pipeline (JIRA_TASK_ID param)
      system-prompt.md   — worker agent instructions
    shared/
      setup-env.sh       — derives JIRA_URL, GH_TOKEN, JENKINS_USERNAME, BASE_BRANCH
      setup-claude.sh    — copies agent-settings.json, registers atlassian MCP
      setup-workspace.sh — clones repo, checks out feature/task branches
hooks/
  pre-bash-guard.sh      — secondary dangerous-command guard
Jenkinsfile              — Majordomo main job (disableConcurrentBuilds, 60 min timeout)
docs/
  agent-workflow-spec.md — canonical full spec for all stages
```

### Implemented Steps in Majordomo system-prompt.md
- Step 1: Load & validate config.yaml
- Step 2: Schedule check (stub — always proceed)
- Step 3: Poll GH Issues → create Jira Epics + Planning Tasks
- Step 4: Evaluate Planning Tasks → launch planning agent
- Step 5: Plan Approval Spinoff (Approved → create Implementation Tasks → Done)
- Step 6: **STUB** — "Not yet implemented"
- Step 7: **STUB** — "Not yet implemented"
- Step 8: **STUB** — "Not yet implemented"

## Jira API Patterns Already in Use

All Jira access uses REST API with basic auth (`JIRA_EMAIL:JIRA_API_TOKEN`) against
`$JIRA_URL` (which resolves to `https://api.atlassian.com/ex/jira/<cloud-id>`).

Key API patterns established in the existing system prompt:
- JQL search: `GET /rest/api/3/issue/search?jql=...`
- Issue fetch: `GET /rest/api/3/issue/{key}`
- Transitions: `GET /rest/api/3/issue/{key}/transitions` → `POST /rest/api/3/issue/{key}/transitions`
- Create issue: `POST /rest/api/3/issue`
- Add comment: `POST /rest/api/3/issue/{key}/comment`

## Implementation Task Identity

Planning Tasks: `issuetype = Task AND summary ~ "Plan:"` (starts with "Plan:")
Implementation Tasks: all other Tasks (`issuetype = Task AND summary !~ "Plan:"`)

Implementation tasks are created by Step 5 with:
- Title: stage title from spec doc (text after `## Stage N:`)  ← NOTE: stage number NOT in title
- Description: stage description + `spec_doc_path:` + `feature_branch:`
- Status: Open
- Parent: the Epic

## Task Ordering / "Prior Sibling" Determination

The stage number N is **not stored** in the Jira task title (only the text after `Stage N:`
is used as the title). To determine which tasks are "prior":
- Tasks are created in stage order by Step 5
- Use Jira rank field (`customfield_10019`) — lower lexicographic value = created earlier = lower stage number
- Sort sibling implementation tasks by rank; lower-rank tasks are "prior"

## Jenkins Job URLs

Planning agent trigger (from Step 4):
```
http://jenkins.${ROOT_DOMAIN}/job/majordomo-planner/job/${BASE_BRANCH}/buildWithParameters?JIRA_TASK_ID=<id>
```

Worker trigger (assumed from naming convention):
```
http://jenkins.${ROOT_DOMAIN}/job/majordomo-worker/job/${BASE_BRANCH}/buildWithParameters?JIRA_TASK_ID=<id>
```

## Feature→Main PR Mechanics

- Epic description contains GH Issue URL (set during Step 3)
- Feature branch: `feature/<EPIC_KEY>` (e.g. `feature/MDOMO-7`)
- PR check: `gh pr list --repo wcjordan/<repo> --base main --head feature/<epic-id> --state open`
- PR creation: `gh pr create --repo wcjordan/<repo> --base main --head feature/<epic-id> --title ... --body ...`

## Priority Labels

Epic priority is determined by Jira labels: `P0`, `P1`, `P2`
Higher priority = P0 > P1 > P2 > (unlabelled, treated as lowest)

## Prioritization Algorithm (Step 6 + Step 7)

Eligible tasks ranked by:
1. Tasks whose parent Epic has siblings currently `In Progress` or `In Review` (continuity)
2. Epic priority label: P0 > P1 > P2
3. Jira rank of the Epic (customfield_10019, ascending lexicographic)

## Ready Target Policy

- Promote all eligible tasks to `Ready` (one per Epic at a time — a task is only eligible if
  no sibling is In Progress or In Review, so at most one per Epic can become Ready at once)
- Multiple Ready tasks across different Epics in same repo = fine (no collision risk)
- Step 7 selects one Ready task to launch (applies same prioritization)
