# CLAUDE.md

Guidelines and context for Claude agents and contributors working in this repo.

---

## What This Repo Is

**minordomo** is the automated development pipeline itself. Majordomo and its sub-agents live here. This repo is also one of the repos Majordomo manages (Jira project: `MDOMO`).

See [`docs/GETTING_AROUND.md`](docs/GETTING_AROUND.md) for repo structure and stage overview. See [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) for Jira status flows, branching model, and task prioritization.

---

## Trust Model: Agent vs. Local Settings

`shared/agent-settings.json` is the Claude permissions template deployed into every agent container at runtime by `shared/setup-claude.sh`. It is **not** the settings for local development.

Local development uses `.claude/settings.local.json`.

**Agent permissions (from `shared/agent-settings.json`):**
- Allow: `Bash(*)`, `Read(*)`, `Edit(*)`, `Write(*)`, `mcp__atlassian__*`
- Deny: force pushes, `git commit --no-verify`, `git rebase`, `sudo`, `rm -rf /`, GCP metadata endpoint access
- Hook: `shared/pre-bash-guard.sh` runs before every Bash invocation as a secondary safety check

Agents run in ephemeral containers with no sensitive files on disk. Credentials arrive as environment variables injected by Jenkins.

To test the pre-bash-guard hook locally:
```bash
# Should block (exit 1):
echo '{"tool_input": {"command": "git push --force origin main"}}' | shared/pre-bash-guard.sh

# Should allow (exit 0):
echo '{"tool_input": {"command": "git push origin main"}}' | shared/pre-bash-guard.sh
```

---

## Agent Startup Sequence

Every agent container sources these scripts before invoking `claude -p`:

1. `shared/setup-env.sh` — derives `JIRA_URL`, `GH_TOKEN`, `JENKINS_USERNAME`, `BASE_BRANCH`, `JIRA_EMAIL`, `JIRA_API_TOKEN` from Jenkins-injected credentials
2. `shared/setup-claude.sh` — copies `agent-settings.json` to `~/.claude/settings.json`, registers the Atlassian MCP server via `claude mcp add`
3. `shared/setup-workspace.sh <mode>` — clones the target repo, checks out or creates feature/task branches (planning agent and worker only; not Majordomo)

---

## Jira Access

Two access paths, depending on the operation:

- **MCP tools** (`mcp__atlassian__*`) — use for reads where a matching tool exists
- **Jira REST API** — required for transitions, searches, and operations not covered by MCP tools; use `${JIRA_EMAIL}:${JIRA_API_TOKEN}` basic auth against `${JIRA_URL}`

Key REST patterns:
```
JQL search:   GET  ${JIRA_URL}/rest/api/3/issue/search?jql=<encoded>&fields=...&maxResults=100
Issue fetch:  GET  ${JIRA_URL}/rest/api/3/issue/{key}?fields=...
Transitions:  GET  ${JIRA_URL}/rest/api/3/issue/{key}/transitions
              POST ${JIRA_URL}/rest/api/3/issue/{key}/transitions  body: {"transition":{"id":"<id>"}}
Create:       POST ${JIRA_URL}/rest/api/3/issue
Comment:      POST ${JIRA_URL}/rest/api/3/issue/{key}/comment
```

---

## Task Identity & Ordering

**Planning Tasks:** `issuetype = Task AND summary ~ "^Plan:"` — title starts with `Plan:`

**Implementation Tasks:** `issuetype = Task AND summary !~ "^Plan:"` — all other Tasks

Implementation task titles are the text after `## Stage N:` from the spec doc — the stage number itself is not stored in the Jira title.

**Stage ordering within an Epic:** Use Jira rank (`customfield_10019`) — lower lexicographic value = created earlier = lower stage number. Tasks are created in stage order by the Plan Approval Spinoff step (Step 5), so Jira rank reliably reflects stage sequence.

---

## Jenkins Job Trigger URLs

Majordomo triggers sub-agents via Jenkins HTTP API:

```bash
# Planning agent
curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
  "http://jenkins.${ROOT_DOMAIN}/job/majordomo-planner/job/${BASE_BRANCH}/buildWithParameters?JIRA_TASK_ID=<id>"

# Worker
curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
  "http://jenkins.${ROOT_DOMAIN}/job/majordomo-worker/job/${BASE_BRANCH}/buildWithParameters?JIRA_TASK_ID=<id>"
```

---

## Hard Rules for All Agents

- **Never merge PRs directly.** Workers and Majordomo open PRs; humans merge them.
- **Never force-push.** The deny list blocks this; do not attempt workarounds.
- Workers always branch from the current feature branch tip — this ensures each agent picks up the latest spec and any code merged by prior stages.
- Spec docs land on feature branches only via merged PRs from planning agent task branches.

---

## Testing

```bash
make test
```

Runs shellcheck, bats unit tests (`test/bats/`), and a prompt validation script. Run before committing changes to shell scripts or system prompts.
