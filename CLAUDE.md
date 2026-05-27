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

Safety rules are the single source of truth in `shared/safety-rules.yaml`. Run `shared/generate-safety-rules.sh` to regenerate the deny list in `agent-settings.json` and the pattern blocks in `pre-bash-guard.sh`. Use `make check-safety` to verify committed output matches the generator.

To test the pre-bash-guard hook locally:
```bash
# Should block (exit 1):
echo '{"tool_input": {"command": "git push --force origin main"}}' | shared/pre-bash-guard.sh

# Should allow (exit 0):
echo '{"tool_input": {"command": "git push origin main"}}' | shared/pre-bash-guard.sh
```

---

## Agent Startup Sequence

Every agent container sources `shared/bootstrap.sh <mode>` before invoking `claude -p`, which runs these scripts in order:

1. `shared/setup-env.sh` — derives `JIRA_URL`, `GH_TOKEN`, `JENKINS_USERNAME`, `BASE_BRANCH`, `JIRA_EMAIL`, `JIRA_API_TOKEN` from Jenkins-injected credentials
2. `shared/setup-claude.sh` — copies `agent-settings.json` to `~/.claude/settings.json`, registers the Atlassian MCP server via `claude mcp add`
3. `shared/setup-workspace.sh <mode>` — clones the target repo, checks out or creates feature/task branches (planning agent and worker only; not Majordomo)

---

## Pipeline Helper Functions

`shared/pipeline-helpers.sh` provides shared utilities for agent system prompts. Source it early in a run:

```bash
source shared/pipeline-helpers.sh
```

Available functions:
- **`beads_task_id_by_title <title>`** — finds a beads task ID by exact title, searching both open and in_progress
- **`has_needs_input <repo> <issue_number>`** — returns exit 0 if the GH issue carries the `needs-input` label, exit 1 otherwise
- **`extract_priority <labels_json>`** — extracts the first P0–P4 label from a GH labels JSON array, defaulting to `P2`

`shared/jira-transition.sh` is a standalone script for transitioning a Jira issue to a named status. Usage:

```bash
shared/jira-transition.sh "<issue_key>" "<status_name>"
# Example:
shared/jira-transition.sh "${jira_task_id}" "In Review"
```

Reads `JIRA_URL`, `JIRA_EMAIL`, and `JIRA_API_TOKEN` from the environment. Exits non-zero with an error message if credentials are missing, the GET request fails, or the named status is not in the transitions list.

---

## Jira Access

Two access paths, depending on the operation:

- **MCP tools** (`mcp__atlassian__*`) — use for reads where a matching tool exists
- **Jira REST API** — required for transitions, searches, and operations not covered by MCP tools; use `${JIRA_EMAIL}:${JIRA_API_TOKEN}` basic auth against `${JIRA_URL}`

Key REST patterns:
```
JQL search:   GET  ${JIRA_URL}/rest/api/3/search/jql?jql=<encoded>&fields=...&maxResults=100
Issue fetch:  GET  ${JIRA_URL}/rest/api/3/issue/{key}?fields=...
Transitions:  GET  ${JIRA_URL}/rest/api/3/issue/{key}/transitions
              POST ${JIRA_URL}/rest/api/3/issue/{key}/transitions  body: {"transition":{"id":"<id>"}}
Create:       POST ${JIRA_URL}/rest/api/3/issue
Comment:      POST ${JIRA_URL}/rest/api/3/issue/{key}/comment
```

---

## Task Identity & Ordering

**Planning Tasks:** A task is a Planning Task if and only if its summary **starts with** the literal prefix `Plan:` (case-sensitive, no leading whitespace). A task with "plan" elsewhere in the title (e.g. "Implement deployment plan") is an Implementation Task.

**Implementation Tasks:** Every Task that does not start with `Plan:`.

JQL `~` / `!~` is a text-contains operator — it cannot enforce "starts with". Always apply a second, client-side filter after any Jira query that distinguishes Planning from Implementation Tasks:

```python
# After fetching tasks from Jira, re-filter in code before acting
planning = [t for t in tasks if t["fields"]["summary"].startswith("Plan:")]
implementation = [t for t in tasks if not t["fields"]["summary"].startswith("Plan:")]
```

Use `summary ~ "Plan:"` / `summary !~ "Plan:"` in JQL only as a coarse pre-filter to reduce result size. Never rely on JQL alone to make this distinction.

Implementation task titles are the text after `## Stage N:` from the spec doc — the stage number itself is not stored in the Jira title.

**Stage ordering within an Epic:** Use Jira rank (`customfield_10019`) — lower lexicographic value = created earlier = lower stage number. Tasks are created in stage order by the Plan Approval Spinoff step (Step 5), so Jira rank reliably reflects stage sequence.

---

## Jenkins Job Trigger URLs

Majordomo triggers sub-agents via `shared/jenkins-trigger.sh <job-name> <beads-task-id>`. The script reads `JENKINS_USERNAME`, `JENKINS_API_KEY`, `ROOT_DOMAIN`, and `BASE_BRANCH` from the environment and POSTs to the Jenkins `buildWithParameters` endpoint:

```bash
# Planning agent
shared/jenkins-trigger.sh minordomo-plan "<beads_plan_id>"

# Worker
shared/jenkins-trigger.sh minordomo-step "<beads_impl_id>"
```

---

## Hard Rules for All Agents

- **Never merge PRs directly.** Workers and Majordomo open PRs; humans merge them.
- **Never force-push.** The deny list blocks this; do not attempt workarounds.
- Workers always branch from the current feature branch tip — this ensures each agent picks up the latest spec and any code merged by prior stages.
- Spec docs land on feature branches only via merged PRs from planning agent task branches.
- **Put deterministic commands in shared scripts, not inline in `system-prompt.md`.** Any shell command that fetches data, checks state, or calls an API belongs in a file under `shared/` and is invoked by name from the prompt. Inline shell is only acceptable for truly one-off, single-step logic that cannot be extracted. This keeps system prompts readable and commands testable.

---

## Testing

```bash
make test
```

Runs shellcheck, bats unit tests (`test/bats/`), and a prompt validation script. Run before committing changes to shell scripts or system prompts.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

### Beads `bd list` Status Behavior

`bd list --json` without a `--status` flag returns only **open** tasks. Tasks in `in_progress` status (claimed tasks) are excluded from the default listing. To find in-progress tasks, use `bd list --status=in_progress --json`. When looking up a task by title (e.g., to close or update it) that may have been claimed, search across all statuses:

```bash
# Search open only (default):
bd list --json | ...

# Search including in_progress:
{ bd list --json; bd list --status=in_progress --json; } | python3 -c "import sys, json; print(json.dumps([t for batch in [json.loads(l) for l in sys.stdin if l.strip()] for t in batch]))" | ...
```

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
