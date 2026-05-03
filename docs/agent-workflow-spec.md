# Claude Code Agent Workflow Spec

## Overview

A multi-agent system for autonomously picking up, planning, and implementing development tasks. The system is orchestrated by a **Majordomo agent** that runs on a schedule, evaluates work across projects, manages Claude usage limits, and launches **worker agents** to execute implementation tasks. A separate **planning agent** handles ticket grooming through an iterative human Q&A loop.

The stages are ordered so that the system can take over building itself as early as possible. After Stage 3, a GH Issue can be filed for the remaining stages and the system will plan and implement them autonomously.

---

## Architecture Summary

```
Human Request (GH Issue)
        │
        ▼
  Majordomo Agent (scheduled Jenkins job)
        │
        ├── Creates Jira Epic/Story + Planning Task
        │
        ├── Evaluates planning tasks → launches Planning Agent
        │
        ├── Evaluates implementation tasks → promotes to Ready
        │
        └── Launches single Worker Agent (passes Jira task ID)
                │
                └── Implements task, commits, opens PR, marks In Review
```

**Work sources:**
- **GitHub Issues** — human-created feature requests (filtered by allowlist)

**Projects tracked by Majordomo:**

| Repo | Jira Project Key |
|---|---|
| `minordomo` | `MDOMO` |
| `chalk` | `CHALK` |
| `gcp-setup` | `INFRA` |
| `forester` | `FSTR` |

**Jira instance:** `https://${JIRA_DOMAIN}.atlassian.net` (Jira Cloud). `JIRA_DOMAIN` is a configurable environment variable.

---

## Running Agents

Each agent (Majordomo, planning agent, worker) is a non-interactive Claude Code invocation:

```bash
claude -p "<system prompt>" --allowlist-file majordomo/claude-allowlist.json
```

The system prompt tells the agent how to access its Jira ticket, how the system is running it, and where to post questions or results.

**Majordomo launches sub-agents** by triggering parameterized Jenkins jobs via the Jenkins API, passing the Jira ticket ID as a job parameter.

**Credentials** are injected by Jenkins as environment variables:
- `JIRA_DOMAIN` — Jira Cloud subdomain
- `ANTHROPIC_API_KEY` — for Claude
- `GH_TOKEN` — for `gh` CLI GitHub interactions
- Jira auth is handled via the Atlassian MCP server (credentials provided as env vars to the MCP)

**Sandboxing:**

Agents run in ephemeral containers with no sensitive files on disk. The repo's `.claude/settings.json` uses a broad allowlist with a targeted deny list:

```json
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Edit(*)", "Write(*)", "mcp__atlassian__*"],
    "deny": [
      "Bash(git push --force*)",
      "Bash(git push -f *)",
      "Bash(git commit --no-verify*)",
      "Bash(git rebase*)",
      "Bash(sudo *)",
      "Bash(rm -rf /*)",
      "Bash(curl *metadata.google.internal*)",
      "Bash(curl *169.254.169.254*)"
    ]
  }
}
```

A `PreBashCommand` hook (`hooks/pre-bash-guard.sh`) provides a secondary check for dangerous patterns. Container-level network restrictions (allowlisting outbound to `api.anthropic.com`, `api.github.com`, `*.atlassian.net`) are recommended.

---

## Jira Ticket Hierarchy

```
Epic (linked to GH Issue)
└── Story (if multi-feature complexity)
    ├── Planning Task  (task/PROJ-43 branch; grooming, Q&A, spec doc)
    └── Implementation Tasks (one per stage from approved plan)
```

Implementation tasks are leaf nodes — no further planning needed. They become available to the Majordomo once created and all prior sibling stages are Done.

---

## GH Issue ↔ Jira Epic Linking

When Majordomo creates a Jira Epic for a GH Issue it:
1. Adds the GH Issue URL to the Jira Epic description
2. Adds the Jira Epic key to the GH Issue description (via `gh` CLI)
3. Applies the label `jira-epic-created` to the GH Issue

On subsequent runs, Majordomo filters out all GH Issues that already have the `jira-epic-created` label — this is the idempotency gate. No cross-system querying is needed.

---

## Jira Status Flows

### Planning Task Status Flow
```
Open → In Progress → Needs Input → Open → ... → In Progress → In Review → Approved → Done
```

| Status | Meaning |
|---|---|
| Open | Ready for Majordomo to assign to planning agent (or human has answered questions) |
| In Progress | Planning agent is actively working |
| Needs Input | Agent posted questions on the Jira ticket; blocks re-queue until human answers and resets to Open |
| In Review | Agent opened a PR (spec doc branch → feature branch); awaiting human review and merge |
| Approved | Human merged spec PR and is satisfied with the multi-stage plan; ready to spin off tasks |
| Done | Implementation tasks created; planning ticket closed |

**Human actions:**
- Answer questions on ticket → set ticket back to **Open**
- Approve final spec → merge PR → set ticket to **Approved**

**Key distinction:**
- **Needs Input** — agent has questions or needs clarification before it can proceed. Majordomo will not re-queue until human resets to Open. This is the async equivalent of the synchronous Q&A exercise.
- **In Review** — a PR is open (spec doc or implementation). No Majordomo re-queue; human reviews, merges, and advances the ticket manually.

### Implementation Task Status Flow
```
Open → Ready → In Progress → In Review → Done
```

| Status | Meaning |
|---|---|
| Open | Created, not yet evaluated by Majordomo |
| Ready | Majordomo has selected it; worker can pick it up |
| In Progress | Worker agent is actively implementing |
| In Review | Worker opened PR; awaiting human review and merge |
| Needs Input | Worker encountered a blocker requiring human input |
| Done | Human merged PR and marked ticket complete |

---

## Branching Model

All branch merges require a human-reviewed PR. Workers and the Majordomo never merge directly across branches.

```
main
└── feature/PROJ-42              (epic/story branch)
    ├── task/PROJ-43             (planning task; spec doc PR → feature/PROJ-42)
    ├── task/PROJ-44             (impl stage 1; PR → feature/PROJ-42)
    ├── task/PROJ-45             (impl stage 2; PR → feature/PROJ-42)
    └── task/PROJ-46             (impl stage 3; PR → feature/PROJ-42)
```

- **feature branch** — created by the planning agent; holds the canonical spec doc (e.g. `docs/planning/PROJ-42-spec.md`) after the planning PR is merged
- **task branches** — created by the agent (planning or worker) at launch time, always branching from the current feature branch tip; named `task/<ticket-id>`
- **task → feature PRs** — opened by the agent on completion; reviewed and merged by human
- **feature → main PR** — opened by the Majordomo when all subtasks of the Story are Done; reviewed and merged by human; PR description references the originating GH Issue and summarizes what the epic delivered

**Key principle:** Agents never pre-create branches. Branching at launch time ensures each agent starts from the latest feature branch tip, including spec and code updates from prior merged stages.

---

## Spec Document

The implementation plan lives as a markdown file on the feature branch (e.g. `docs/planning/PROJ-42-spec.md`). It is the canonical source of truth for the full multi-stage plan. It arrives on the feature branch when the planning agent's PR is merged.

Each implementation task ticket contains:
- A concise description of its specific stage
- A reference to the spec doc path and feature branch
- Acceptance criteria for its stage

When a stage's implementation reveals necessary changes to the plan, the spec doc is updated and included in that stage's PR against the feature branch. The next stage's worker branches from the updated feature branch and reads the current spec.

---

## Stage 1 — Foundation & Trust Boundaries

**Goal:** Establish the secure ingestion pipeline and Jira structure before any automation runs.

### 1.1 GitHub Issue Allowlist Filter

- Maintain a config file (e.g. `majordomo/config.yaml`) with an `allowed_gh_users` list
- Majordomo only considers GH Issues authored by users on this list
- Issues from non-allowed users are silently ignored (no labels, no Jira tickets)

### 1.2 Jira Project & Schema Setup

Create four Jira Cloud projects (all on `https://${JIRA_DOMAIN}.atlassian.net`):

| Project | Key |
|---|---|
| minordomo | `MDOMO` |
| chalk | `CHALK` |
| gcp-setup | `INFRA` |
| forester | `FSTR` |

For each project:
- Configure issue hierarchy: Epic → Story → Task
- Define all required statuses: `Open`, `In Progress`, `In Review`, `Ready`, `Needs Input`, `Approved`, `Done`
- Define priority labels: `P0`, `P1`, `P2`

### 1.3 Majordomo Skeleton

- Implement Majordomo as a Claude Code agent running as a Jenkins job (`claude -p`)
- Majordomo reads `majordomo/config.yaml` for allowed users, project list, and limits config
- Majordomo produces a structured run log; logs stored in Jenkins build logs for auditability
- Jenkins job designed to be portable to GH Actions (no Jenkins-specific logic in Majordomo itself; orchestration concerns isolated to Jenkinsfile)
- No scheduling yet — trigger manually for initial testing

---

## Stage 2 — GH Issue Ingestion & Minimal Worker

**Goal:** Establish the full end-to-end loop — from GH Issue to implemented task — in its simplest form. This thin slice proves the pipeline before adding planning automation.

### 2.1 GH Issue → Jira Epic/Story

- Majordomo polls GH Issues across configured repos
- Filters by `allowed_gh_users`
- Skips issues that already have the `jira-epic-created` label (idempotent)
- Creates **Epic** + Planning **Task** under the Epic
- Adds the GH Issue URL to the Jira Epic description
- Adds the Jira Epic key to the GH Issue description via `gh` CLI
- Applies the `jira-epic-created` label to the GH Issue
- Planning Task created in status **Open**

### 2.2 Minimal Worker

A thin worker implementation sufficient to execute one task end-to-end:

- Majordomo manually triggered with a hardcoded or manually specified Jira task ID
- No prioritization logic, no usage limits, no scheduling — human selects the task
- Worker:
  1. Reads Jira task (stage description, acceptance criteria, spec doc path, feature branch reference)
  2. Checks out the feature branch tip and creates a new task branch (e.g. `task/PROJ-44`)
  3. Reads the spec doc from the feature branch
  4. Implements the stage
  5. Fixes any failing tests before committing (no WIP commits)
  6. Once tests pass: commits, pushes, opens PR against the feature branch
  7. Transitions Jira task to **In Review**
  8. Exits
- Human reviews PR, merges, and marks task **Done**
- Majordomo detects all Story subtasks Done → opens feature → main PR referencing the GH Issue

### 2.3 Task Sizing

- Target: ~30 minutes average, ~1 hour maximum per task
- Planning agent (Stage 3) will enforce this; for Stage 2, human manually sizes tasks
- Monitor task durations and failure rates; if lost-work on Jenkins crash becomes a problem, WIP commits can be introduced as a follow-on design change

---

## Stage 3 — Planning Agent Loop

**Goal:** Automate ticket grooming through iterative research and human Q&A, producing sized implementation tasks the worker can execute autonomously.

**After this stage is complete, file a GH Issue for Stages 4–7. The system will plan and build the rest of itself.**

### 3.1 Planning Agent Trigger

- Majordomo identifies Planning Tasks in status **Open**
- Transitions task to **In Progress** and launches Planning Agent as a Jenkins job with the Jira task ID
- Jenkins job designed to be portable to GH Actions

### 3.2 Planning Agent Behavior

On each run the Planning Agent:

1. Reads the Jira Planning Task (description, comments, linked GH Issue, existing research docs)
2. Checks out or creates the feature branch for the Epic (e.g. `feature/PROJ-42`)
3. Creates a task branch off the feature branch tip (e.g. `task/PROJ-43`)
4. Reads any existing research doc from the branch to resume prior context
5. Performs research relevant to the task
6. Identifies open questions blocking the plan

**If blocking questions remain:**
- Posts questions as a structured comment on the Jira ticket
- Commits current research doc to the task branch
- Transitions ticket to **Needs Input**
- Exits

**If no blocking questions remain:**
- Produces a multi-stage implementation plan sized so each stage averages ~30 minutes and does not exceed ~1 hour of implementation work
- Each stage defined such that tests pass and a PR can be opened after each stage
- Commits final spec doc to the task branch (e.g. `docs/planning/PROJ-42-spec.md`)
- Opens a PR from the task branch against the feature branch
- Posts plan summary on the Jira ticket
- Transitions ticket to **In Review** for human approval

### 3.3 Human Q&A Flow

- Human reviews questions posted on the Jira ticket (under **Needs Input**)
- Human answers in a comment on the ticket
- Human sets ticket back to **Open**
- On next Majordomo run, Planning Agent is re-launched, reads prior research doc from task branch, continues

### 3.4 Plan Approval & Task Spinoff

- Human reviews final spec PR on the task branch
- Human merges the PR (spec doc lands on feature branch)
- Human transitions Planning Task to **Approved**
- On next Majordomo run, Majordomo reads the approved spec doc from the feature branch and creates one Jira Implementation Task per stage under the same Epic/Story
- Each task ticket includes: stage description, acceptance criteria, reference to spec doc path and feature branch
- All implementation tasks created in status **Open**
- Planning Task transitioned to **Done**

---

## ✦ Handoff Point

After Stage 3 is operational, file a GH Issue describing Stages 4–7. The Majordomo will ingest it, the Planning Agent will research and produce a spec, and the Worker will implement each stage. Stages 4–7 below serve as the specification for that work.

---

## Stage 4 — Majordomo Prioritization & Ready Promotion

**Goal:** Majordomo intelligently selects which implementation tasks are ready to be worked next, replacing the manual task selection from Stage 2.

### 4.1 Eligibility Criteria

A task is eligible for **Ready** if:
- Status is **Open**
- All prior sibling tasks under the same Epic/Story are **Done** (enforces stage sequencing)
- No other task in the same Epic/Story is currently **In Progress** or **In Review**

### 4.2 Prioritization Order

Majordomo ranks eligible tasks by:
1. Tasks whose parent Story/Epic has other stages already in flight (continuity)
2. Priority label: `P0` > `P1` > `P2` of the Epic
3. Jira rank (manual ordering within a project) of the Epic

### 4.3 Ready Targets

- Majordomo aims to maintain **at least one** `Ready` task per repo
- Multiple `Ready` tasks per repo are allowed if they won't collide (different epics/stories)
- Majordomo transitions eligible tasks to **Ready** and selects one to launch
- Majordomo submits a Jenkins job to run a worker task to implement the Ready ticket, passing the ticket ID as a parameter

### 4.4 Feature → Main PR

- When Majordomo detects all subtasks of a Story are **Done**, it opens a PR from the feature branch to `main`
- PR description references the originating GH Issue and summarizes what the story delivered
- Human reviews and merges; Majordomo never merges directly

---

## Stage 5 — Usage Limits & Scheduling

**Goal:** Respect Claude usage limits and run only at appropriate times.

### 5.1 Usage Check

Before launching any worker, Majordomo:
- Makes an OAuth request to `https://api.anthropic.com/api/oauth/usage` to retrieve weekly usage
  - Reference implementation: [`claude_quota.py`](https://github.com/slopware/claude-quota/blob/main/claude_quota.py)
  - **Note:** This endpoint is unofficial and undocumented; verify it works before relying on it and handle gracefully if it changes
- Checks weekly usage against a configurable threshold (default: **50%**)
- If usage ≥ threshold → logs decision, exits without launching a worker

### 5.2 Time-of-Day Gating

Majordomo enforces a configurable schedule:
- **Allowed windows** (default): weekday daytimes and overnight
- **Blocked windows** (default): weekends

Config in `majordomo/config.yaml`:
```yaml
schedule:
  allowed_days: [Mon, Tue, Wed, Thu, Fri]
  allowed_hours: ["00:00-08:00", "18:00-23:59"]
  weekend_override: false
```

### 5.3 Jenkins Scheduling

- Majordomo runs as a Jenkins job on a defined cron schedule
- Jenkins configured with **no concurrency** (one Majordomo run at a time)
- Jenkinsfile isolates all scheduling and trigger logic so migration to GH Actions is straightforward

---

## Stage 6 — Spec Evolution

**Goal:** Harden the worker with spec update handling.

### 6.1 Spec Update Handling

- If implementation of a stage reveals necessary changes to the plan, worker updates the spec doc and includes it in the PR
- Next stage worker branches from updated feature branch tip, picking up the revised spec automatically

---

## Stage 7 — Failure Handling & Recovery

**Goal:** Ensure no task gets permanently stuck and lost work is minimized.

### 7.1 Claude Crash / Needs Input

If the worker agent crashes or halts awaiting input:
- Any completed work is committed and pushed to the task branch before exit where possible
- Worker posts a comment on the Jira ticket describing where it stopped and why
- Worker transitions ticket to **Ready** (can retry) or **Needs Input** (human answer required)
- Majordomo will re-queue a **Ready** task on next run; **Needs Input** tasks wait for human intervention

### 7.2 Jenkins Crash (Sweep Job)

If the Jenkins job itself crashes, the worker cannot self-recover. A dedicated sweep job handles this:

- Runs on a regular schedule (e.g. every 4 hours)
- Finds any Implementation Task in **In Progress** for more than **12 hours**
- Transitions those tickets back to **Ready**
- Posts a comment noting the reset and timestamp
- Majordomo will re-queue on next run

### 7.3 Partial / Silent Failure

For failures not caught by the sweep job (e.g. worker completes and opens a PR but the implementation is incorrect):
- CI runs on the PR and surfaces test failures
- Human PR review catches behavioral issues
- Human closes the PR with feedback, resets ticket to **Ready** or **Needs Input** as appropriate

### 7.4 Planning Agent Failure

Same principles apply to the planning agent:
- Crash → commit research doc to task branch, post comment, reset to **Open**
- Needs Input → transition to **Needs Input**, human answers and resets to **Open**
- Sweep job covers Jenkins-level crashes for planning jobs as well (same 12-hour threshold)

---

## Future Considerations

- **GH Actions migration** — when ready, Jenkinsfile logic moves to workflow YAML; Majordomo, planning agent, worker, and sweep job code remain unchanged
- **Parallel workers** — Majordomo launches N workers; Jenkins parallel builds; `In Progress` transition is the atomic claim
- **WIP commits** — if task failure rates or durations warrant it, introduce WIP commits to task branch mid-task to reduce lost work on Jenkins crash
