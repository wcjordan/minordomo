# Stage 2 Implementation Plan

## Scope

Stage 2 delivers two things:

- **2.1 GH Issue Ingestion** — Majordomo polls GitHub Issues and creates Jira Epics + Planning Tasks
- **2.2 Minimal Worker** — a worker Jenkins job that takes a Jira task ID, implements the task, opens a PR, and marks the ticket In Review

The worker is triggered directly by a human with a `JIRA_TASK_ID` parameter in Stage 2. Majordomo wiring (Step 6) is deferred to Stage 4.

Feature → main PR detection (mentioned in the original Stage 2.2 description) is also deferred to Stage 4.

---

## Files

### 1. `docs/agent-workflow-spec.md` — minor edit

Remove the feature→main PR bullet from the Stage 2.2 description and annotate it as Stage 4 scope. No other changes.

---

### 2. `majordomo/system-prompt.md` — implement Step 3

Replace the "NOT YET IMPLEMENTED" stub in Step 3 (Poll GitHub Issues → Create Jira Epics) with real logic:

- For each project in config, run `gh issue list --repo wcjordan/<repo> --state open --json number,title,body,author,labels`
- Filter issues to those authored by users in `allowed_gh_users`
- Skip any issue that already has the `jira-epic-created` label (idempotency gate)
- For each remaining issue:
  - Create a Jira Epic under the project's `jira_key` with the GH Issue URL in the description
  - Create a Planning Task under the Epic in status **Open**
  - Add the Jira Epic key as a comment on the GH Issue via `gh issue comment`
  - Apply the `jira-epic-created` label via `gh issue edit --add-label`
- Log results per issue (created / skipped) in the step log

Step 6 (Launch Worker) stays as its existing stub — human triggers the worker directly in Stage 2.

---

### 3. `majordomo/jenkins/worker/Jenkinsfile` — new file

Parameterized Jenkins pipeline job for the worker agent.

**Parameter:** `JIRA_TASK_ID` (string, required) — only parameter; REPO and FEATURE_BRANCH are derived by the workspace setup script.

**Structure mirrors the Majordomo Jenkinsfile:**
- `agent none` at pipeline level, `agent { kubernetes { ... } }` at stage level
- Same majordomo-runner image from GAR
- Same resource requests/limits (500m–1000m CPU, 1–2Gi memory)
- `disableConcurrentBuilds()` and `timestamps()` options
- 120-minute timeout

**Credentials injected:**
- `CLAUDE_CODE_OAUTH_TOKEN` → `claude-code-oauth-token`
- `GH_APP` → `github-app`
- `JIRA_TOKEN` → `jira_api_key`

**Shell steps:**
1. Derive `JIRA_DOMAIN`, `JENKINS_USERNAME`, `JIRA_USERNAME`, `GH_TOKEN` from injected credentials — extract into a shared script (`majordomo/jenkins/shared/setup-env.sh`) sourced by both Majordomo and worker Jenkinsfiles
2. Deploy `majordomo/agent-settings.json` to `.claude/settings.json` and register the Atlassian MCP server — extract into a shared script (`majordomo/jenkins/shared/setup-claude.sh`)
3. Run `majordomo/jenkins/worker/setup-workspace.sh` to derive REPO and FEATURE_BRANCH and set up the task branch (see below)
4. Run: `claude -p "$(cat majordomo/jenkins/worker/system-prompt.md)"` from inside the cloned repo directory, with `JIRA_TASK_ID` and `FEATURE_BRANCH` in the environment

### 3a. `majordomo/jenkins/worker/setup-workspace.sh` — new file

Bash script that runs before Claude and prepares the git workspace:

1. **Derive REPO** — extract the Jira project key from `JIRA_TASK_ID` (e.g. `MDOMO` from `MDOMO-44`), then look up the matching `repo` value in `majordomo/config.yaml`
2. **Derive FEATURE_BRANCH** — call the Jira REST API (`curl`) to fetch the task, extract the parent Epic key from the response, construct `feature/<EPIC_KEY>`
3. **Clone and branch**:
   ```bash
   gh repo clone wcjordan/$REPO
   cd $REPO
   git checkout $FEATURE_BRANCH
   git checkout -b task/$JIRA_TASK_ID
   git push -u origin task/$JIRA_TASK_ID
   ```
4. Export `REPO` and `FEATURE_BRANCH` for subsequent steps in the Jenkinsfile

---

### 4. `majordomo/jenkins/worker/system-prompt.md` — new file

Worker system prompt. The worker runs non-interactively (`claude -p`) and must complete all steps and exit without prompting for input.

**Environment available:**
- `JIRA_TASK_ID` — the Jira task to implement
- `JIRA_DOMAIN` — Jira Cloud subdomain
- `GH_TOKEN` — for `gh` CLI
- Atlassian MCP (`mcp__atlassian__*`) for Jira reads/writes

The worker starts with the target repo already cloned and the `task/<JIRA_TASK_ID>` branch already checked out and pushed (done by the Jenkinsfile). The worker's working directory is the root of the cloned repo.

**Steps the worker executes:**

1. **Read the Jira task** via MCP — extract: spec doc path, stage description, acceptance criteria
2. **Read the spec doc** at the path specified in the Jira task
3. **Implement the stage** per the stage description and acceptance criteria
4. **Verify tests pass** — run the repo's test suite; fix failures before committing (no WIP commits)
5. **Commit and push** — commit all changes to `task/<JIRA_TASK_ID>` and push
6. **Open a PR** — `gh pr create` targeting `$FEATURE_BRANCH`; PR title and description derived from the stage description and Jira task
7. **Transition Jira task to In Review** via MCP
8. **Emit a run log** to stdout (JSON, similar format to Majordomo run log) and exit 0

On any unrecoverable error: log the error, exit 1 (Jenkins will mark the build failed).

---

## Out of Scope for Stage 2

- Majordomo Step 6 (worker launch) — Stage 4
- Feature → main PR detection (Step 7) — Stage 4
- Task prioritization and Ready promotion (Step 5) — Stage 4
- Planning agent (Step 4) — Stage 3
- Usage limits and scheduling (Step 2) — Stage 5
