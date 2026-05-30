# CLAUDE.md

Guidelines and context for Claude agents and contributors working in this repo.

---

## What This Repo Is

**minordomo** is the automated development pipeline itself. Majordomo and its sub-agents live here. This repo is also one of the repos Majordomo manages.

See [`docs/GETTING_AROUND.md`](docs/GETTING_AROUND.md) for repo structure and stage overview. See [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) for branching model and task prioritization.

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

1. `shared/setup-env.sh` — derives `GH_TOKEN`, `JENKINS_USERNAME`, `BASE_BRANCH` from Jenkins-injected credentials
2. `shared/setup-claude.sh` — copies `agent-settings.json` to `~/.claude/settings.json`
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

`shared/apply-needs-input.sh` encapsulates the three-step needs-input protocol (apply label, post comment, reset beads task). Usage:

```bash
shared/apply-needs-input.sh "<repo>" "<issue_number>" "<beads_task_id>" "<comment_body>"
```

Exits non-zero and logs to stderr identifying the failed step if any step fails.

---

## Task Identity & Ordering

**Planning Tasks:** Plan tasks exist in beads only. A beads task is a Plan task if and only if its title **starts with** the literal prefix `Plan:` (case-sensitive, no leading whitespace).

**Implementation Tasks:** Every beads task that does not start with `Plan:` or `Story:`.

Implementation task titles are the text after `## Stage N:` from the spec doc — the stage number itself is not stored in the task title.

**Stage ordering within an Epic:** determined by the beads dependency chain — each Stage N task depends on Stage N−1, so `bd ready` surfaces them in sequence.

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
