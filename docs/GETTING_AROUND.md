# Getting Around

Reference for the repo structure and stage overview. For branching model, spec documents, and task prioritization, see [`WORKFLOWS.md`](WORKFLOWS.md).

---

## Repository Structure

```
minordomo/
├── majordomo/
│   ├── Jenkinsfile          — Majordomo main job (disableConcurrentBuilds, 60 min timeout)
│   └── system-prompt.md     — Majordomo agent instructions (Steps 1–9)
├── minordomo-plan/
│   ├── Jenkinsfile          — Planning agent job (parameterized: BEADS_TASK_ID)
│   └── system-prompt.md     — Planning agent instructions
├── minordomo-step/
│   ├── Jenkinsfile          — Worker agent job (parameterized: BEADS_TASK_ID)
│   └── system-prompt.md     — Worker agent instructions
├── minordomo-librarian/
│   ├── Jenkinsfile          — Librarian job (daily cron, 60 min timeout)
│   └── system-prompt.md     — Librarian agent instructions
├── minordomo-sweep/
│   └── Jenkinsfile          — Stale task sweep job (cron: every 4 hours, 15 min timeout)
├── minordomo-container-builder/
│   ├── Dockerfile           — Container image for all agent jobs
│   ├── Jenkinsfile          — Builds and pushes the image to GAR (weekly cron)
│   └── requirements.txt     — Python deps bundled into the image
├── shared/
│   ├── config.yaml          — Central config: allowed users, projects, schedule, usage limits
│   ├── agent-settings.json  — Claude permissions allowlist/denylist deployed into agent containers
│   ├── pre-bash-guard.sh    — Secondary Bash safety hook (referenced by agent-settings.json)
│   ├── setup-env.sh         — Derives runtime env vars from Jenkins credentials
│   ├── setup-claude.sh      — Deploys agent settings
│   ├── setup-workspace.sh   — Clones repo, checks out feature/task branches
│   ├── notify-failure.py    — Sends SES failure email; always exits 0 (notification failure must not break builds)
│   └── notify-pr-discord.js — Sends Discord message for each PR URL found in run log; always exits 0
├── test/
│   ├── bats/                — Bats unit tests for shared shell scripts
│   ├── fixtures/            — Test fixture data
│   ├── run-all.sh           — Test runner (invoked by `make test`)
│   ├── shellcheck.sh        — Shellcheck linter
│   └── validate-prompts.py  — System prompt validation script
├── docs/
│   ├── GETTING_AROUND.md    — This file
│   ├── WORKFLOWS.md         — Branching model, spec docs, prioritization
│   ├── agent-workflow-spec.md — System capabilities and Majordomo run sequence
│   ├── FUTURE_WORK.md       — Planned capabilities not yet implemented
│   └── setup/
│       ├── aws-ses-setup.md — AWS SES setup guide (IAM policy, email verification, Jenkins credentials)
│       └── discord-webhook-setup.md — Discord webhook setup guide (Jenkins credential, channel config)
├── CLAUDE.md                — Agent trust model and implementation patterns
├── README.md                — Setup and configuration
└── Makefile                 — `make test`
```

---

## System Capabilities

The pipeline is fully operational. Key capabilities:

| Capability | Description |
|---|---|
| GH Issue ingestion | Polls GH Issues → creates Planning Tasks |
| Planning agent loop | Research, Q&A, spec doc, plan approval spinoff |
| Task prioritization | Ready promotion, continuity/priority/rank ordering |
| Worker agents | Branch, implement, open PR |
| Feature→main PRs | Auto-opened when all Stage tasks are closed; includes doc cleanup |
| Beads coordination | `bd` CLI for task tracking; `bd ready` for task selection |
| Planning priority guard | Defers planning if higher-priority implementation work is available |
| PR sync | Closes beads Stage tasks for merged implementation PRs |
| Failure notifications | SES email on pipeline failure; triggered by hard Jenkins failure or agent-reported errors |
| Discord PR notifications | Discord message for each PR opened by the pipeline; `discord-webhook-url` Jenkins credential required |
| Stale task sweep | Resets tasks orphaned by Jenkins crashes back to open on a 4-hour schedule |
| Documentation Librarian | Daily cron job: detects structural and content drift in docs, integrates agent suggestions from `docs/suggestions/`, opens a PR to main when changes are needed |

See [`docs/agent-workflow-spec.md`](agent-workflow-spec.md) for the full capability descriptions and Majordomo run sequence. See [`docs/FUTURE_WORK.md`](FUTURE_WORK.md) for planned capabilities not yet implemented.
