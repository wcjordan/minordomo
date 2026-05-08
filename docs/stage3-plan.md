# Stage 3 Implementation Plan

## Scope

Stage 3 delivers the Planning Agent loop — automated ticket grooming through iterative research and human Q&A, producing sized implementation tasks the worker can execute autonomously.

- **3.1 Planning Agent Trigger** — Majordomo identifies Open Planning Tasks and launches the planning agent Jenkins job
- **3.2 Planning Agent Behavior** — the planning agent researches, asks questions, and produces a multi-stage spec
- **3.3 Human Q&A Flow** — Needs Input → human answers → Open → re-launch cycle
- **3.4 Plan Approval & Task Spinoff** — Majordomo reads approved spec docs and creates Implementation Tasks

---

## Files

### 1. `majordomo/jenkins/planning-agent/Jenkinsfile` — new file

Mirrors the worker Jenkinsfile. Parameterized pipeline job for the planning agent.

**Parameter:** `JIRA_TASK_ID` (string, required) — only parameter; REPO, EPIC_KEY, and FEATURE_BRANCH are derived by the workspace setup script.

**Structure:**
- `agent none` at pipeline level, `agent { kubernetes { ... } }` at stage level
- Same `majordomo-runner` image from GAR
- Same resource requests/limits (500m–1000m CPU, 1–2Gi memory)
- `timestamps()` option; no `disableConcurrentBuilds()` (multiple planning agents may run in parallel)
- 120-minute timeout

**Credentials injected:**
- `CLAUDE_CODE_OAUTH_TOKEN` → `claude-code-oauth-token`
- `GH_APP` → `github-app`
- `JIRA_ACCT` → `jira-api-key`

**Shell steps:**
1. Source `majordomo/jenkins/shared/setup-env.sh`
2. Source `majordomo/jenkins/shared/setup-claude.sh`
3. Source `majordomo/jenkins/planning-agent/setup-workspace.sh`
4. Run `claude -p "$(cat ../majordomo/jenkins/planning-agent/system-prompt.md)"` from inside the cloned repo directory

---

### 2. `majordomo/jenkins/planning-agent/setup-workspace.sh` — new file

Bash script run before Claude that prepares the git workspace. Follows the same pattern as `majordomo/jenkins/worker/setup-workspace.sh` with two differences: the feature branch may not exist yet, and the task branch must handle re-runs.

1. **Derive REPO** — extract the Jira project key from `JIRA_TASK_ID`, look up the matching `repo` in `majordomo/config.yaml`
2. **Derive EPIC_KEY and FEATURE_BRANCH** — call the Jira REST API to fetch the planning task, extract the parent Epic key, construct `feature/<EPIC_KEY>`
3. **Set up git auth** — `gh auth setup-git`
4. **Clone the target repo** — `gh repo clone wcjordan/$REPO`
5. **Create or check out the feature branch:**
   - If `origin/$FEATURE_BRANCH` exists: `git checkout $FEATURE_BRANCH`
   - Otherwise: `git checkout -b $FEATURE_BRANCH main && git push -u origin $FEATURE_BRANCH`
6. **Create or check out the task branch:**
   - If `origin/task/$JIRA_TASK_ID` exists (re-run after Needs Input): `git checkout task/$JIRA_TASK_ID && git pull`
   - Otherwise: `git checkout -b task/$JIRA_TASK_ID && git push -u origin task/$JIRA_TASK_ID`
7. Export `REPO`, `EPIC_KEY`, and `FEATURE_BRANCH` for the Claude invocation

---

### 3. `majordomo/jenkins/planning-agent/system-prompt.md` — new file

Planning agent system prompt. Runs non-interactively (`claude -p`); must complete all steps and exit without prompting for input.

**Environment available:**
- `JIRA_TASK_ID` — the Planning Task to work on
- `EPIC_KEY` — the parent Epic key
- `FEATURE_BRANCH` — the feature branch (e.g. `feature/MDOMO-42`)
- Atlassian MCP (`mcp__atlassian__*`) for Jira reads/writes
- `gh` CLI authenticated via `GH_TOKEN`
- Working directory: root of the cloned target repo, on the `task/$JIRA_TASK_ID` branch

**Steps the planning agent executes:**

1. **Read the Jira Planning Task** via MCP — extract the description, all comments, and any text or image file attachments
2. **Read the Jira Epic** via MCP — extract the description, all comments, file attachments, and the linked GH Issue URL from the Epic description
3. **Fetch the GH Issue** — use `gh issue view` to get the full issue body and comment thread for requirements context
4. **Load prior research** — read all files under `docs/research/$EPIC_KEY/` if the directory exists; these persist across re-runs
5. **Perform research** — explore the codebase, read relevant files, and gather context needed to produce a sound implementation plan; save research notes to `docs/research/$EPIC_KEY/` (one or more `.md` files, named descriptively)
6. **Identify questions** — flag anything that is vague or underspecified and for which no clear precedent exists in the codebase; these are not limited to blockers — if the right approach is genuinely unclear and the repo provides no example to extrapolate from, ask

**If questions remain:**
- Post questions as a structured comment on the Jira Planning Task (numbered list, one question per line)
- Commit current state of `docs/research/$EPIC_KEY/` to `task/$JIRA_TASK_ID` and push
- Transition the Planning Task to **Needs Input**
- Emit run log and exit 0

**If no questions remain:**
- Produce a multi-stage implementation plan. Each stage must:
  - Average ~30 minutes and not exceed ~1 hour of implementation work
  - Leave tests passing and a PR openable when it completes
  - Be independent enough that a worker can execute it from a clean branch checkout
- Write the spec doc to `docs/planning/$EPIC_KEY-spec.md`. Use this structure for each stage so Majordomo can parse them:
  ```
  ## Stage N: <title>

  ### Description
  <what this stage implements>

  ### Acceptance Criteria
  - <criterion>
  - <criterion>
  ```
- Commit the spec doc (and any remaining research docs) to `task/$JIRA_TASK_ID` and push
- Open a PR from `task/$JIRA_TASK_ID` targeting `$FEATURE_BRANCH`:
  ```bash
  gh pr create \
    --base "$FEATURE_BRANCH" \
    --title "Plan: <epic title>" \
    --body "<summary of the proposed plan with stage breakdown>"
  ```
- Post a comment on the Jira Planning Task summarizing the plan (stage count, brief description of each stage)
- Transition the Planning Task to **In Review**
- Emit run log and exit 0

**Run log format** (same structure as Majordomo and worker):
```json
{
  "run_id": "<BUILD_TAG or ISO timestamp>",
  "timestamp": "<ISO 8601 UTC>",
  "jira_task_id": "<JIRA_TASK_ID>",
  "status": "success|failure",
  "steps": [
    {"step": "read_planning_task", "status": "ok"},
    {"step": "read_epic", "status": "ok"},
    {"step": "read_gh_issue", "status": "ok"},
    {"step": "load_research", "status": "ok", "files_found": 2},
    {"step": "research", "status": "ok"},
    {"step": "identify_questions", "status": "ok", "questions": 0},
    {"step": "write_spec", "status": "ok", "spec_path": "docs/planning/MDOMO-42-spec.md"},
    {"step": "open_pr", "status": "ok", "pr_url": "https://github.com/wcjordan/chalk/pull/7"},
    {"step": "jira_transition", "status": "ok", "new_status": "In Review"}
  ],
  "errors": []
}
```

---

### 4. `majordomo/system-prompt.md` — three changes

#### 4a. Step 4 (Evaluate Planning Tasks) — implement it

Replace the "NOT YET IMPLEMENTED" stub with real logic:

1. Query Jira for Planning Tasks in status `Open` across all configured projects
2. If any Planning Task is already `In Progress`: log decision and set `planning_agent_launched: false`; skip to next step (at most one planning agent per run)
3. Otherwise, pick the highest-priority eligible task (by Epic priority label P0 > P1 > P2, then Jira rank), transition it to `In Progress`, and trigger the `majordomo-planning-agent` Jenkins job:
   ```bash
   curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
     "http://jenkins.${ROOT_DOMAIN}/job/majordomo-planning-agent/buildWithParameters?JIRA_TASK_ID=<task_id>"
   ```
4. Record `planning_agent_launched: true` in the step log

#### 4b. New Step 5 (Plan Approval Spinoff) — insert between old Step 4 and old Step 5

1. Query Jira for Planning Tasks in status `Approved` across all configured projects
2. For each approved planning task:
   a. Derive the target repo from the project key (same lookup as worker/planning-agent)
   b. Run `gh auth setup-git` and `gh repo clone wcjordan/$REPO` into a temp directory
   c. Check out `$FEATURE_BRANCH`
   d. Read `docs/planning/$EPIC_KEY-spec.md` from the feature branch
   e. Parse the stages — each `## Stage N:` section yields one Implementation Task
   f. Create one Jira Implementation Task per stage under the same Epic, in status `Open`, with:
      - Title: the stage title
      - Description: the stage description
      - Acceptance criteria: from the spec doc
      - Custom fields (or description text): `spec_doc_path: docs/planning/$EPIC_KEY-spec.md` and `feature_branch: $FEATURE_BRANCH`
   g. Transition the Planning Task to `Done`
3. Record in the step log: number of approved tasks processed and total implementation tasks created

#### 4c. Renumber old Steps 5 → 6, 6 → 7, 7 → 8

Update step names in instructions and run log format to match new numbering.

---

## Out of Scope for Stage 3

- Majordomo Step 6 (automated worker launch) — Stage 4
- Feature → main PR detection (Step 8) — Stage 4
- Task prioritization and Ready promotion (Step 7) — Stage 4
- Usage limits and scheduling (Step 2) — Stage 5
- Spec evolution on worker re-runs — Stage 6
- Failure handling and sweep job — Stage 7
