# Getting Around

Reference for the repo structure and stage overview. For Jira status flows, branching model, spec documents, and task prioritization, see [`WORKFLOWS.md`](WORKFLOWS.md).

---

## Repository Structure

```
minordomo/
├── majordomo/
│   ├── Jenkinsfile          — Majordomo main job (disableConcurrentBuilds, 60 min timeout)
│   └── system-prompt.md     — Majordomo agent instructions (Steps 1–8)
├── minordomo-plan/
│   ├── Jenkinsfile          — Planning agent job (parameterized: JIRA_TASK_ID)
│   └── system-prompt.md     — Planning agent instructions
├── minordomo-step/
│   ├── Jenkinsfile          — Worker agent job (parameterized: JIRA_TASK_ID)
│   └── system-prompt.md     — Worker agent instructions
├── minordomo-container-builder/
│   ├── Dockerfile           — Container image for all agent jobs
│   ├── Jenkinsfile          — Builds and pushes the image to GAR (weekly cron)
│   └── requirements.txt     — Python deps bundled into the image
├── shared/
│   ├── config.yaml          — Central config: allowed users, projects, schedule, usage limits
│   ├── agent-settings.json  — Claude permissions allowlist/denylist deployed into agent containers
│   ├── pre-bash-guard.sh    — Secondary Bash safety hook (referenced by agent-settings.json)
│   ├── setup-env.sh         — Derives runtime env vars from Jenkins credentials
│   ├── setup-claude.sh      — Deploys agent settings and registers Atlassian MCP
│   └── setup-workspace.sh   — Clones repo, checks out feature/task branches
├── test/
│   ├── bats/                — Bats unit tests for shared shell scripts
│   ├── fixtures/            — Test fixture data
│   ├── run-all.sh           — Test runner (invoked by `make test`)
│   ├── shellcheck.sh        — Shellcheck linter
│   └── validate-prompts.py  — System prompt validation script
├── docs/
│   ├── GETTING_AROUND.md    — This file
│   ├── WORKFLOWS.md         — Jira status flows, branching model, spec docs, prioritization
│   └── agent-workflow-spec.md — Full spec for remaining unimplemented stages (5–7)
├── CLAUDE.md                — Agent trust model and implementation patterns
├── README.md                — Setup and configuration
└── Makefile                 — `make test`
```

---

## Stage Overview

| Stage | Description | Status |
|---|---|---|
| 1 | Foundation & trust boundaries: allowlist, Jira project schema, Majordomo skeleton | Done |
| 2 | GH Issue ingestion and minimal worker end-to-end | Done |
| 3 | Planning agent loop: research, Q&A, spec doc, plan approval spinoff | Done |
| 4 | Majordomo prioritization, Ready promotion, feature→base PRs | Done |
| 5 | Usage limits (Claude API quota check) and time-of-day scheduling | Not implemented |
| 6 | Spec evolution: worker updates spec doc in-flight when plan changes | Not implemented |
| 7 | Failure handling: crash recovery, sweep job for stuck In Progress tasks | Not implemented |

After Stage 3, Stages 5–7 can be filed as GH Issues and the system will plan and implement them autonomously.
