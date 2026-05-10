# Getting Around

Reference for the repo structure, Jira workflows, branching model, and stage overview.

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
│   └── GETTING_AROUND.md    — This file
├── CLAUDE.md                — Agent trust model and implementation patterns
├── README.md                — Setup and configuration
└── Makefile                 — `make test`
```

---

## Jira Ticket Hierarchy

```
Epic (linked to GH Issue)
└── Planning Task     (summary starts with "Plan:")
└── Implementation Tasks  (one per stage from the approved plan)
```

- Epics and Planning Tasks are created by Majordomo when a new GH Issue is ingested (Step 3).
- Implementation Tasks are spun off by Majordomo when the Planning Task reaches `Approved` (Step 5). One task per `## Stage N:` section in the spec doc.
- Implementation tasks are leaf nodes — no further planning required. They become eligible for promotion once all prior sibling tasks are `Done`.

**Task identity:**
- Planning Tasks: `issuetype = Task AND summary ~ "^Plan:"`
- Implementation Tasks: `issuetype = Task AND summary !~ "^Plan:"`

---

## Jira Status Flows

### Planning Task

```
Open → In Progress → Needs Input → Open → ... → In Progress → In Review → Approved → Done
```

| Status | Meaning |
|---|---|
| Open | Ready for Majordomo to assign to a planning agent (or human has answered questions) |
| In Progress | Planning agent is actively working |
| Needs Input | Agent posted questions on the ticket; Majordomo will not re-queue until human resets to Open |
| In Review | Agent opened a PR (spec doc branch → feature branch); human reviews and merges |
| Approved | Human merged the spec PR; Majordomo will spin off Implementation Tasks on next run |
| Done | Implementation Tasks created; planning ticket closed |

**Human actions required:**
- Answer questions → set ticket back to **Open**
- Approve spec → merge PR → set ticket to **Approved**

### Implementation Task

```
Open → Ready → In Progress → In Review → Done
```

| Status | Meaning |
|---|---|
| Open | Created; not yet promoted by Majordomo |
| Ready | Eligible and queued; Majordomo will launch a worker |
| In Progress | Worker agent is actively implementing |
| In Review | Worker opened PR; awaiting human review and merge |
| Needs Input | Worker encountered a blocker requiring human input |
| Done | Human merged PR and marked ticket complete |

---

## Branching Model

All merges across branches require a human-reviewed PR. Agents never merge directly.

```
<base_branch> (bootstrap by default)
└── feature/PROJ-42              (Epic/Story branch)
    ├── task/PROJ-43             (planning task; spec doc PR → feature/PROJ-42)
    ├── task/PROJ-44             (impl stage 1; PR → feature/PROJ-42)
    ├── task/PROJ-45             (impl stage 2; PR → feature/PROJ-42)
    └── task/PROJ-46             (impl stage 3; PR → feature/PROJ-42)
```

- **Feature branch** — created by the planning agent; holds the canonical spec doc (`docs/planning/PROJ-42-spec.md`) after the planning PR is merged
- **Task branches** — created by the agent at launch time, always branching from the current feature branch tip; named `task/<ticket-id>`
- **task → feature PRs** — opened by the agent on completion; reviewed and merged by human
- **feature → base PRs** — opened by Majordomo when all Implementation Tasks of an Epic are `Done`; reviewed and merged by human

Agents never pre-create branches. Branching at launch time ensures each agent starts from the latest feature branch tip, picking up the spec and any code changes from prior merged stages.

---

## Spec Documents

The implementation plan lives as a markdown file on the feature branch (`docs/planning/PROJ-42-spec.md`). It is created by the planning agent on its task branch and arrives on the feature branch when the planning PR is merged.

Each `## Stage N:` section in the spec yields one Jira Implementation Task. The stage number is not stored in the Jira title — only the text after `## Stage N:` is used. Stage ordering is determined by Jira rank (`customfield_10019`), which reflects creation order.

When a stage's implementation reveals necessary changes to the plan, the spec doc is updated and included in that stage's PR. The next stage's worker branches from the updated feature branch and reads the current spec.

---

## Prioritization (Steps 6 & 7)

**Promoting to Ready (Step 6):** An Open Implementation Task is eligible for `Ready` if:
1. All prior siblings (lower Jira rank) are `Done`
2. No sibling at any rank is `In Progress` or `In Review`

At most one task per Epic can be promoted at a time (the second check ensures this).

**Selecting a worker target (Step 7):** From all `Ready` tasks, Majordomo excludes tasks whose Epic has a sibling `In Progress` or `In Review`, then ranks the remainder:
1. Tasks whose Epic has other Implementation Tasks already `Done` (continuity — Epic is making progress)
2. Epic priority label: `P0` > `P1` > `P2` > unlabelled
3. Epic Jira rank (`customfield_10019`, ascending lexicographic = manual ordering)

Majordomo launches at most one worker per run, and skips worker launch if a planning agent was launched that run.

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

---

## Future Directions

- **GH Actions migration** — when ready, Jenkinsfile logic moves to workflow YAML; Majordomo, planning agent, worker, and sweep job code remain unchanged
- **Parallel workers** — Majordomo launches N workers; `In Progress` transition is the atomic claim
- **WIP commits** — if task failure rates or durations warrant it, introduce mid-task commits to reduce lost work on Jenkins crash
