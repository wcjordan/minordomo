# Replacing Jira with GitHub Issues + Beads

This document captures the plan for replacing Atlassian Jira with a combination of
GitHub Issues (human-facing tracking) and [Beads](https://github.com/gastownhall/beads)
(agent-facing task coordination).

---

## Concept Mapping

| Jira concept | Replacement |
|---|---|
| Epic | GitHub Issue (already exists) |
| `jira-epic-created` GH label | `beads-ingested` GH label |
| Planning Task (`Plan:`) | Beads parent task → subtask `bd-xxxx.1` |
| Implementation Tasks (Stage N) | Beads subtasks `bd-xxxx.2`, `.3`, etc. |
| Jira rank (stage ordering) | Beads dependency graph (stage N+1 blocks on stage N) |
| Priority labels P0/P1/P2 on Epic | Same labels on GH Issue; Majordomo reads via GH API |
| Status transitions (REST API) | `bd update --claim`, `bd update --status` |
| `In Review` status | `in-review` GH label on Issue + beads status |
| `Needs Input` status | `needs-input` GH label on Issue + GH comment by agent |
| `JIRA_TASK_ID` Jenkins param | `BEADS_TASK_ID` (beads hash, e.g. `bd-a3f8.2`) |
| Atlassian MCP | Removed; beads CLI + GH API only |

---

## Infrastructure Changes

### Add: Dolt sql-server on Kubernetes

Beads requires a persistent `dolt sql-server` because agents run in ephemeral Jenkins
containers (the embedded `.beads/` DB is gitignored and not present after a fresh clone).

Deploy one StatefulSet + PVC + Service per repo, or a single shared instance with one
database per repo. The Bitnami MySQL Helm chart with a `dolthub/dolt-sql-server` image
override is a practical starting point. Expected resource footprint for this workload:
~64Mi memory, minimal CPU.

### Add: Jenkins env vars

| Variable | Purpose |
|---|---|
| `BEADS_SERVER_HOST` | Hostname of the dolt sql-server service |
| `BEADS_SERVER_PORT` | Port (default 3306) |

These replace `JIRA_CLOUD_ID`, `JIRA_EMAIL`, and `JIRA_API_TOKEN`.

### Remove

- Atlassian Cloud subscription
- `mcp-atlassian` MCP server registration in `shared/setup-claude.sh`

---

## Code Changes by Component

### `shared/config.yaml`

Drop `jira_key` from each project entry; keep `repo` only.

### `shared/setup-env.sh`

Replace Jira credential derivation with passthrough of `BEADS_SERVER_HOST` and
`BEADS_SERVER_PORT`.

### `shared/setup-claude.sh`

Remove `claude mcp add atlassian`. Add `bd config set server ...` so agents connect
to the shared dolt server.

### `shared/setup-workspace.sh`

Replace the Jira REST lookup used to derive `EPIC_KEY` and `FEATURE_BRANCH`:

```bash
# Before
curl ... "${JIRA_URL}/rest/api/3/issue/${JIRA_TASK_ID}?fields=parent"

# After
bd show "${BEADS_TASK_ID}" --json | jq -r '.parent'
```

### `shared/agent-settings.json`

Remove `mcp__atlassian__*` from the allow list. No new MCP entry needed.

### Majordomo step 3 — GH Issues → ingest

Replace Jira Epic creation with:

```bash
bd create "Plan: <issue title>" --priority <N>
```

Apply `beads-ingested` GH label instead of `jira-epic-created`. Store the GH Issue URL
in the beads task description.

### Majordomo step 4 — sync PR merge status

Replace the Jira `In Review` JQL query with:

```bash
bd list --status in_review --json
```

Replace the transition REST call with:

```bash
bd update <id> --status done
```

### Majordomo step 5 — pick planning task

```bash
# Before: JQL search + REST transition
# After:
bd ready --json | jq 'select(.title | startswith("Plan:"))'
bd update <id> --claim
```

### Majordomo step 6 — spinoff implementation tasks

On spec PR merge, parse spec doc stages and create beads subtasks with explicit
dependencies so stage ordering is enforced by the dependency graph:

```bash
bd create "Stage 1: ..." --parent <planning-task-id>
bd create "Stage 2: ..." --parent <planning-task-id>
bd dep add bd-x.3 bd-x.2   # stage 3 blocked by stage 2
bd dep add bd-x.2 bd-x.1   # stage 2 blocked by stage 1
```

Because `bd ready` surfaces tasks with no open blocking dependencies, **step 7
(promote Implementation Tasks) is eliminated** — beads handles promotion automatically.

### Majordomo step 8 — launch worker

```bash
# Surface eligible tasks
bd ready --json | jq 'select(.title | startswith("Plan:") | not)'

# Sort candidates by GH Issue priority label (P0 > P1 > P2) via GH API
# Claim atomically
bd update <id> --claim

# Pass to Jenkins
curl ... "buildWithParameters?BEADS_TASK_ID=<id>"
```

### Majordomo step 9 — feature → base PRs

Replace Jira Epic query with GH Issues filtered by `beads-ingested` label. Check all
subtasks done before opening PR:

```bash
bd list --parent <id> --json | jq 'all(.status == "done")'
```

---

## "Needs Input" Flow (new)

Agents hitting a blocker apply the `needs-input` GH label to the linked Issue and post
a comment explaining what's needed. Majordomo steps 5 and 8 skip tasks whose linked
GH Issue carries `needs-input`. A human removes the label to unblock — no Jira status
reset required.

---

## Migration / Cutover

No data migration is needed. Existing in-flight Jira work can finish naturally. For new
work, strip the `jira-epic-created` label from GH Issues (or ignore it in step 3) so
Majordomo re-ingests them into beads.

---

## Phased Rollout

1. **Stand up Dolt server on k8s** — deploy, verify connectivity from a Jenkins agent
2. **Replace step 3** — ingest GH Issues into beads; run alongside Jira briefly to validate
3. **Replace setup scripts** — `setup-env.sh`, `setup-claude.sh`, `setup-workspace.sh`
4. **Replace steps 4–9** — swap Jira API calls one step at a time; each is independently testable
5. **Strip `jira-epic-created` labels** — triggers re-ingestion of open GH Issues into beads
6. **Decommission Atlassian Cloud subscription**

---

## Risks and Open Questions

- **Beads maturity** — newer project; run step 3 in parallel with Jira briefly before full cutover to catch edge cases
- **Cross-repo priority sorting** — Majordomo must fetch GH Issue labels for each candidate task's parent to compare P0/P1/P2 across repos; slightly more GH API calls than a single JQL query today
- **Dolt server availability** — a single pod is a single point of failure; configure a liveness probe and PVC-backed restart policy from day one
