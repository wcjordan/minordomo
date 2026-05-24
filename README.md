# minordomo

Automated development pipeline. A scheduled **Majordomo** agent ingests GitHub Issues, drives them through planning (via a Planning Agent) and implementation (via Worker agents), and keeps Jira tickets accurate at every step.

See [`docs/GETTING_AROUND.md`](docs/GETTING_AROUND.md) for repo structure and stage overview, [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) for Jira status flows and branching model, and [`CLAUDE.md`](CLAUDE.md) for agent trust model and implementation patterns.

---

## Architecture

```
GitHub Issues → Majordomo (Jenkins cron)
                    ├── Planning Agent (Jenkins job)
                    └── Worker Agent   (Jenkins job)
```

Majordomo runs on a schedule. On each run it:
1. Ingests new GH Issues → creates Jira Epics + Planning Tasks
2. Launches a Planning Agent for the highest-priority open planning task
3. Spins off Implementation Tasks from approved plans
4. Promotes eligible Implementation Tasks to Ready
5. Launches a Worker Agent to implement the top Ready task
6. Opens feature → main PRs when all subtasks of an Epic are Done

The pipeline is fully operational: it ingests GH Issues, drives them through planning and implementation, and opens feature→main PRs. It also includes beads-based task coordination, a planning priority guard, and automatic cleanup of planning artifacts. Planned future work (usage limits, spec evolution, failure handling) is captured in [`docs/FUTURE_WORK.md`](docs/FUTURE_WORK.md).

---

## Prerequisites

- Jenkins with the Kubernetes plugin
- GKE cluster with a node pool Jenkins can schedule pods on
- Google Artifact Registry repo at `us-east4-docker.pkg.dev/${GCP_PROJECT}/default-gar`
- Jira Cloud instance with projects `MDOMO`, `CHALK`, `INFRA`, `FSTR`
- `gh` CLI available in CI (bundled in the Docker image)

---

## One-Time Setup

### 1. Jenkins Credentials

These are provided by the `gcp-setup` repo. Add them in Jenkins → Manage Jenkins → Credentials:

| Credential ID | Type | Description |
|---|---|---|
| `claude-code-oauth-token` | Secret text | Claude Code OAuth token (`claude setup-token`) |
| `jenkins-api-key` | Secret text | Jenkins API key (generate at `<ROOT>/user/<username>/security/`) |
| `jira-api-key` | Secret text | Jira API token (generate at id.atlassian.com → Service Accounts) |
| `github-app` | GitHub App | GitHub App providing `GH_TOKEN` at runtime |
| `jenkins-gke-sa` | Secret file | GCP service account JSON with `roles/artifactregistry.writer` (build jobs only) |

Also add a global environment variable `JIRA_CLOUD_ID` from `https://<domain>.atlassian.net/_edge/tenant_info`.

### 2. Build and Push the Docker Image

All agents run inside a container built from `minordomo-container-builder/Dockerfile`. Build and push it before running Majordomo for the first time, and whenever the Dockerfile or `minordomo-container-builder/requirements.txt` changes.

Create a Jenkins pipeline job pointing to `minordomo-container-builder/Jenkinsfile` and trigger it manually. Or build locally:

```bash
# From repo root
docker build -f minordomo-container-builder/Dockerfile -t minordomo-image:local .

# Push to GAR (requires gcloud auth)
GAR_REPO="us-east4-docker.pkg.dev/${GCP_PROJECT}/default-gar"
docker tag minordomo-image:local ${GAR_REPO}/minordomo-image:latest
docker push ${GAR_REPO}/minordomo-image:latest
```

### 3. Create Jenkins Pipeline Jobs

| Job name | Jenkinsfile path | Trigger |
|---|---|---|
| `majordomo` | `majordomo/Jenkinsfile` | Manual trigger; cron scheduling planned as part of Stage 5 |
| `majordomo-build-runner` | `minordomo-container-builder/Jenkinsfile` | Weekly cron (Sundays ~2 AM); manual as needed |
| `minordomo-plan` | `minordomo-plan/Jenkinsfile` | Triggered by Majordomo |
| `minordomo-step` | `minordomo-step/Jenkinsfile` | Triggered by Majordomo |

For each: New Item → Pipeline → "Pipeline script from SCM" → point to this repo and the Jenkinsfile path above.
For each Jenkins pipeline:
- Under the GitHub branch source, setup:
  - Filter by name
  - Status Check Properties → Skip publishing status checks
- Under Property strategy:
  - Suppress automatic SCM triggering
- Discard old items
  - Days to keep old items: 60

---

## Configuration

`shared/config.yaml` is the central config file read on every Majordomo run.

```yaml
allowed_gh_users:        # GitHub users whose issues Majordomo will process
  - wcjordan

base_branch: bootstrap   # branch that new feature branches are created from

projects:                # repos tracked and their Jira project keys
  - repo: minordomo
    jira_key: MDOMO
  ...

schedule:                # Stage 5: time-of-day gating (not yet enforced)
  allowed_days: [Mon, Tue, Wed, Thu, Fri]
  allowed_hours: ["00:00-08:00", "18:00-23:59"]

usage:                   # Stage 5: Claude usage limits (not yet enforced)
  weekly_threshold_pct: 50
```

To add a new repo: add an entry to `projects` and create the corresponding Jira project.

---

## Local Development

Local `claude` / Claude Code usage in this repo uses `.claude/settings.local.json`, not `shared/agent-settings.json`. The agent settings are only deployed inside Jenkins job containers.

```bash
make test   # shellcheck + bats unit tests + prompt validation
```
