# Getting Around

Reference for the repo structure and stage overview. For Jira status flows, branching model, spec documents, and task prioritization, see [`WORKFLOWS.md`](WORKFLOWS.md).

---

## Repository Structure

```
minordomo/
├── majordomo/
│   ├── Jenkinsfile          — Majordomo main job (disableConcurrentBuilds, 60 min timeout)
│   └── system-prompt.md     — Majordomo agent instructions (Steps 1–9)
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
│   ├── setup-workspace.sh   — Clones repo, checks out feature/task branches
│   └── notify-failure.py    — Sends SES failure email; always exits 0 (notification failure must not break builds)
├── test/
│   ├── bats/                — Bats unit tests for shared shell scripts
│   ├── fixtures/            — Test fixture data
│   ├── run-all.sh           — Test runner (invoked by `make test`)
│   ├── shellcheck.sh        — Shellcheck linter
│   └── validate-prompts.py  — System prompt validation script
├── docs/
│   ├── GETTING_AROUND.md    — This file
│   ├── WORKFLOWS.md         — Jira status flows, branching model, spec docs, prioritization
│   ├── agent-workflow-spec.md — System capabilities and Majordomo run sequence
│   ├── FUTURE_WORK.md       — Planned capabilities not yet implemented
│   └── setup/
│       └── aws-ses-setup.md — AWS SES setup guide (IAM policy, email verification, Jenkins credentials)
├── CLAUDE.md                — Agent trust model and implementation patterns
├── README.md                — Setup and configuration
└── Makefile                 — `make test`
```

---

## System Capabilities

The pipeline is fully operational. Key capabilities:

| Capability | Description |
|---|---|
| GH Issue ingestion | Polls GH Issues → creates Jira Epics + Planning Tasks |
| Planning agent loop | Research, Q&A, spec doc, plan approval spinoff |
| Task prioritization | Ready promotion, continuity/priority/rank ordering |
| Worker agents | Branch, implement, open PR |
| Feature→main PRs | Auto-opened when all Stage tasks are closed; includes doc cleanup |
| Beads coordination | `bd` CLI mirrors Jira hierarchy; `bd ready` for task selection |
| Planning priority guard | Defers planning if higher-priority implementation work is available |
| PR sync | Auto-transitions Jira on merged PRs |
| Failure notifications | SES email on pipeline failure; triggered by hard Jenkins failure or agent-reported errors |

See [`docs/agent-workflow-spec.md`](agent-workflow-spec.md) for the full capability descriptions and Majordomo run sequence. See [`docs/FUTURE_WORK.md`](FUTURE_WORK.md) for planned capabilities not yet implemented.
