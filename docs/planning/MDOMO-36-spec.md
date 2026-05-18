# Replacing Jira with GitHub Issues + Beads

This document is the implementation spec for replacing Atlassian Jira with a combination of
GitHub Issues (human-facing tracking) and [Beads](https://github.com/gastownhall/beads)
(agent-facing task coordination).

---

## Concept Mapping (Reference)

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

## Needs Input Flow (Reference)

This is new behavior with no Jira equivalent. When an agent hits a blocker it cannot resolve:

1. Agent applies the `needs-input` GH label to the linked Issue via `gh issue edit`
2. Agent posts a comment on the Issue explaining what's needed
3. Majordomo steps 5 and 8 skip any task whose linked GH Issue carries `needs-input`
4. A human removes the label to unblock — no status reset required

The agent-side behavior is added to `minordomo-plan/system-prompt.md` in Stage 6 and
`minordomo-step/system-prompt.md` in Stage 7.

---

## Stage 1: Write Dolt sql-server Helm chart

### Description

Create a Helm chart at `helm/dolt-server/` in this repo that deploys a persistent Dolt
sql-server. Beads agents connect to this server because they run in ephemeral Jenkins
containers where the embedded `.beads/` DB is not available after a fresh clone.

The chart should include:

- `StatefulSet` with one replica using the `dolthub/dolt-sql-server` image
- `PersistentVolumeClaim` attached to the pod for durable storage
- `Service` (ClusterIP) exposing port 3306
- `ConfigMap` or `values.yaml` for image tag, storage size, and resource limits

Use the existing Helm chart at `https://github.com/wcjordan/chalk/tree/main/helm` as a
structural reference. Expected resource footprint: ~64Mi memory, minimal CPU.

A single shared Dolt instance with one database per managed repo is preferred over one
StatefulSet per repo.

This stage does not deploy anything — it produces the chart only.

### Acceptance Criteria

- `helm lint helm/dolt-server/` passes with no errors or warnings
- `helm template helm/dolt-server/ | kubectl create --dry-run=client -f -` exits 0
  (`kubectl apply --dry-run=client` requires a live server for 3-way merge; `kubectl create --dry-run=client` is equivalent for structural validation)
- The rendered manifest includes a StatefulSet, PVC, and Service

---

## Stage 2: Deploy Dolt server and verify Jenkins connectivity

### Description

Deploy the `helm/dolt-server/` chart to the Kubernetes cluster and confirm that Jenkins
build agents can reach it.

Steps:

1. Create `helm/minordomo-cd-setup/` — a one-time local Helm chart that seeds k8s Secrets
   with Jenkins credential annotations (mirrors chalk's `continuous_delivery_setup/`). Deploy
   once locally to create the `dolt-root-password` k8s Secret before the Jenkins job runs:
   ```bash
   helm install minordomo-cd-setup helm/minordomo-cd-setup/ --set doltRootPassword=<value>
   ```
2. Add a `Build and Push Helm Image` stage to `minordomo-container-builder/Jenkinsfile` that
   builds and pushes `jenkins-helm:latest` to GAR. The image (`Dockerfile.helm`) contains
   gcloud-cli, kubectl, and helm.
3. Add a `Deploy Dolt Server` stage to `minordomo-container-builder/Jenkinsfile` that runs
   `helm upgrade --install dolt-server helm/dolt-server/` against the GKE cluster using the
   `jenkins-helm` image. Runs on every build (idempotent).
4. Deploy and confirm the pod reaches `Running` state with the PVC bound.
5. From a Jenkins agent pod, verify connectivity using the k8s DNS name and hardcoded port:
   ```bash
   mysql -h dolt-server.minordomo.svc.cluster.local -P 3306 -u root \
     --execute "SHOW DATABASES;" 2>&1
   ```

### Acceptance Criteria

- `kubectl get pods -l app.kubernetes.io/name=dolt-server` shows a pod in `Running` state with `PVC` bound
- The `mysql` connectivity check above exits 0 from within a Jenkins agent container

### Implementation Notes

- The Dolt server is reachable at `dolt-server.minordomo.svc.cluster.local:3306` — this is
  derived directly from the k8s Service name and namespace and does not need to be stored as
  a Jenkins env var or in gcp-setup.
- Steps 4 and 5 (actual pod deployment and connectivity verification) are operational steps
  that require the `minordomo-container-builder` Jenkins job to run successfully after this
  PR merges.
- The `dolt-root-password` k8s Secret (created by `helm/minordomo-cd-setup/`) must exist
  before the Jenkins job's `Deploy Dolt Server` stage runs, as the dolt-server StatefulSet
  reads the password from it via `secretKeyRef`.

---

## Stage 3: Install beads CLI and configure agent setup scripts

### Description

Install the `bd` CLI into the Jenkins agent container image and wire it into the shared
setup scripts. After this stage, beads is available and configured in every agent run,
but no Majordomo logic reads from or writes to it yet.

Changes:

- **Container image** — add `bd` installation to the Jenkins agent Dockerfile; pin to a
  specific version. Example (v1.0.4):
  ```dockerfile
  RUN BEADS_VERSION=1.0.4 \
      && curl -fsSL "https://github.com/gastownhall/beads/releases/download/v${BEADS_VERSION}/beads_${BEADS_VERSION}_linux_amd64.tar.gz" \
          | tar -xz -C /usr/local/bin bd \
      && bd --version
  ```
- **`shared/setup-env.sh`** — export the three beads env vars that `bd` reads natively.
  The values are derived directly from the k8s Service DNS name; no Jenkins credential or
  gcp-setup entry is required:
  ```bash
  export BEADS_DOLT_SERVER_HOST="dolt-server.minordomo.svc.cluster.local"
  export BEADS_DOLT_SERVER_PORT=3306
  export BEADS_DOLT_SERVER_USER="minordomo"
  ```
- **`.beads/` directory** — commit the beads workspace init for this repo: `metadata.json`
  configured for server mode. The Dolt DB itself is not committed; `bd` connects to the
  server at startup using the env vars above, so no `bd init` call is needed at runtime.
- **`shared/setup-workspace.sh`** — after the git checkout, fix `.beads/` permissions and
  verify the server connection:
  ```bash
  [ -d .beads ] && chmod 700 .beads
  bd dolt show
  bd list
  ```
- **Majordomo Jenkinsfile** — add a `Beads Status` stage that runs `bd stats` and
  `bd list --status=open` after each orchestration pass and appends the output to the
  Jenkins build description. This gives operators a live view of issue state without
  needing direct Dolt access.
- **`scripts/dolt-forward.sh`** — add a helper script for local operator access to the
  in-cluster Dolt server via `kubectl port-forward`. Supports both one-shot commands
  (`scripts/dolt-forward.sh bd list`) and an interactive subshell.

### Acceptance Criteria

- `bd --version` succeeds inside a Jenkins agent container
- `bd dolt show` reports server mode with host `dolt-server.minordomo.svc.cluster.local`
  and port `3306`
- After a workspace checkout, `bd list` returns without error (confirming server connectivity)
- A Majordomo run appends beads stats to the Jenkins build description
- `scripts/dolt-forward.sh bd list --status=open` returns issues from a local machine
- Existing Jira-based pipeline runs complete without regression

---

## Stage 4: Dual-ingest — Majordomo step 3

### Description

Extend Majordomo step 3 (GH Issues → Jira) to also create a beads planning task for each
ingested issue. Jira epic creation is unchanged; beads runs alongside it.

Changes to Majordomo step 3:

```bash
# After existing Jira epic creation — also create a beads task
bd create "Plan: <issue title>" --priority <N> \
  --description "GH Issue: <issue url>"
```

- Apply `beads-ingested` GH label to the issue in addition to `jira-epic-created`
- Store the GH Issue URL in the beads task description (for agent cross-reference)
- Do not remove or modify `jira-epic-created` label behavior

### Acceptance Criteria

- After ingesting a new GH Issue: `bd list --json | jq '[.[] | select(.title | startswith("Plan:"))] | length'`
  equals the count of Jira epics for newly ingested issues
- Each new beads task's description contains the GH Issue URL:
  `bd show <id> --json | jq '.description'` includes `github.com`
- The `beads-ingested` GH label is applied to the issue
- Existing Jira ingestion is unaffected; `jira-epic-created` label still applied

---

## Stage 5: Dual subtask creation — Majordomo step 6

### Description

Extend Majordomo step 6 (spinoff implementation tasks on spec PR merge) to also create
beads subtasks with an explicit dependency chain. Jira task creation is unchanged.

After parsing the spec doc stages, for each stage N create a beads subtask and add a
blocking dependency on stage N−1:

```bash
bd create "Stage 1: <title>" --parent <planning-task-id>
bd create "Stage 2: <title>" --parent <planning-task-id>
bd dep add bd-x.3 bd-x.2   # stage 3 blocked by stage 2
bd dep add bd-x.2 bd-x.1   # stage 2 blocked by stage 1
```

Because `bd ready` surfaces only tasks with no open blocking dependencies, Majordomo step 7
(promote Implementation Tasks) becomes a no-op and can be removed in this stage.

### Acceptance Criteria

- After a spec PR merge: `bd list --parent <id> --json | jq '[.[].title]'` lists all stages
- `bd list --parent <id> --json | jq '[.[].dependencies] | flatten | length'` equals
  `(stage_count - 1)`
- `bd ready --json | jq '[.[] | select(.title | startswith("Stage 1:"))] | length'` equals 1
  (only stage 1 is unblocked)
- Jira implementation task creation is unaffected

---

## Stage 6: Dual-write planning task lifecycle — Majordomo steps 4 and 5

### Description

Extend the planning task pick (step 5) and PR-merge sync (step 4) to also update beads
task state alongside the existing Jira transitions. Add the Needs Input flow to the
planning agent.

**Majordomo step 5 changes:**

```bash
# After existing Jira claim
bd update <id> --claim

# Skip tasks whose linked GH Issue has needs-input label
gh issue view <issue-number> --json labels \
  | jq '.labels[].name' | grep -q needs-input && continue
```

**Majordomo step 4 changes:**

```bash
# After detecting a merged spec PR
bd update <id> --status done
```

**`minordomo-plan/system-prompt.md` changes:**

In the Questions Path, replace the Jira `Needs Input` transition with:

```bash
gh issue edit <issue-number> --add-label needs-input
gh issue comment <issue-number> --body "<numbered question list>"
```

Keep the Jira `Needs Input` transition alongside this for now.

### Acceptance Criteria

- After Majordomo picks a planning task: `bd show <id> --json | jq '.status'` equals `"in_progress"`
- After a spec PR merges: `bd show <id> --json | jq '.status'` equals `"done"`
- A GH Issue with the `needs-input` label is skipped by step 5 (verify with a test issue)
- When the planning agent enters the Questions Path, the `needs-input` label is applied to
  the linked GH Issue

---

## Stage 7: Dual-write worker lifecycle — Majordomo steps 8 and 9

### Description

Extend worker launch (step 8) and epic completion (step 9) to also update beads state.
Add the Needs Input flow to the worker agent.

**Majordomo step 8 changes:**

```bash
# Surface eligible tasks from beads (for validation, still use Jira for actual dispatch)
bd ready --json | jq '[.[] | select(.title | startswith("Plan:") | not)]'

# Sort by GH Issue priority label (P0 > P1 > P2)
# After existing Jira claim
bd update <id> --claim

# Skip tasks whose linked GH Issue has needs-input label (same pattern as step 5)
```

**Majordomo step 9 changes:**

```bash
# Alongside existing Jira epic check
bd list --parent <id> --json | jq 'all(.status == "done")'
```

**`minordomo-step/system-prompt.md` changes:**

When the worker hits an unresolvable blocker, replace (or supplement) the Jira
`Needs Input` transition with:

```bash
gh issue edit <issue-number> --add-label needs-input
gh issue comment <issue-number> --body "<explanation of blocker>"
```

### Acceptance Criteria

- After a worker is launched: `bd show <id> --json | jq '.status'` equals `"in_progress"`
- After a worker's PR merges: `bd show <id> --json | jq '.status'` equals `"done"`
- When all subtasks are done: `bd list --parent <epic-id> --json | jq 'all(.status == "done")'`
  returns `true`
- A GH Issue with `needs-input` is skipped by step 8
- When the worker applies `needs-input`, the GH label appears on the linked Issue

---

## Stage 8: Switch to beads-only reads

### Description

This is the human-gated cutover PR. Merge when the dual-write stages have been validated
across at least one full planning+worker cycle. This stage switches all reads and dispatch
to beads while keeping Jira write calls in place as a safety net.

**Jenkins:**

- Change `buildWithParameters` calls in Majordomo steps 5 and 8 from
  `JIRA_TASK_ID=<id>` to `BEADS_TASK_ID=<id>`

**`shared/setup-workspace.sh`:**

```bash
# Replace Jira REST lookup
# Before:
curl ... "${JIRA_URL}/rest/api/3/issue/${JIRA_TASK_ID}?fields=parent"

# After:
bd show "${BEADS_TASK_ID}" --json | jq -r '.parent'
```

**Majordomo steps 4–9:** Remove Jira JQL queries and REST reads; keep Jira status
transitions and comment writes. Beads becomes the sole source of truth for task state.

**`minordomo-plan/system-prompt.md`:** Replace Jira MCP reads (steps 1–2) with:

```bash
bd show "${BEADS_TASK_ID}" --json   # task metadata + GH Issue URL
gh issue view <number>              # full requirements context
```

Keep the Jira `Needs Input` transition write for now.

**`minordomo-step/system-prompt.md`:** Same — remove any Jira reads; keep Jira writes.

### Acceptance Criteria

- A full planning cycle completes end-to-end using `BEADS_TASK_ID` with no Jira API reads
- A full worker cycle completes end-to-end using `BEADS_TASK_ID` with no Jira API reads
- Jira status transitions are still being written (verify a task reaches `In Review` in Jira
  after a spec PR opens)

---

## Stage 9: Remove Jira writes and all remaining Jira code

### Description

With beads confirmed as the read source of truth, remove all Jira write calls and tear
down the Jira integration entirely.

**Majordomo steps 3–9:** Remove remaining Jira status transitions, comment writes, and
epic creation. Remove dual-write scaffolding.

**`shared/setup-env.sh`:** Remove Jira credential derivation entirely.

**`shared/setup-claude.sh`:** Remove `claude mcp add atlassian`.

**`shared/agent-settings.json`:** Remove `mcp__atlassian__*` from the allow list.

**`shared/config.yaml`:** Drop `jira_key` from each project entry.

**`minordomo-plan/system-prompt.md`** and **`minordomo-step/system-prompt.md`:** Remove
Jira `Needs Input` transition calls; keep only the GH label + comment flow.

**Ops (performed as part of merging this PR):**

1. Strip the `jira-epic-created` label from all open GH Issues so Majordomo re-ingests
   them into beads on the next run
2. Cancel any in-flight Jira-dispatched Jenkins jobs and let them complete or fail naturally
3. Remove `JIRA_CLOUD_ID`, `JIRA_EMAIL`, `JIRA_API_TOKEN` from Jenkins credentials
4. Decommission the Atlassian Cloud subscription after confirming no open Jira work remains

### Acceptance Criteria

- `grep -r 'JIRA_' shared/ majordomo/ minordomo-plan/ minordomo-step/` returns no matches
- `grep -r 'mcp__atlassian__' . --include='*.json' --include='*.sh' --include='*.md' \
  --exclude-dir=docs` returns no matches
- A full planning cycle completes end-to-end with no Jira calls of any kind
- A full worker cycle completes end-to-end with no Jira calls of any kind
