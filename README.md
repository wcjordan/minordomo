# minordomo

Automated development pipeline. A scheduled **Majordomo** agent ingests GitHub Issues, drives them through planning (via a Planning Agent) and implementation (via Worker agents), and keeps Jira tickets accurate at every step.

See [`docs/agent-workflow-spec.md`](docs/agent-workflow-spec.md) for the full design.

---

## Architecture

```
GitHub Issues → Majordomo (Jenkins cron)
                    ├── Planning Agent (Jenkins job, Stage 3)
                    └── Worker Agent   (Jenkins job, Stage 2)
```

Majordomo runs on a schedule. On each run it:
1. Ingests new GH Issues → creates Jira Epics + Planning Tasks
2. Launches Planning Agents for open planning tasks
3. Promotes eligible Implementation Tasks to Ready
4. Launches a Worker Agent to implement a Ready task
5. Opens feature → main PRs when all story tasks are Done

**Stages 2–7 are not yet implemented.** See the system prompt stubs in `majordomo/system-prompt.md`.

---

## Prerequisites

- Jenkins at `http://jenkins.${env.ROOT_DOMAIN}/` with the Kubernetes plugin
- GKE cluster with a node pool Jenkins can schedule pods on
- Google Artifact Registry repo at `us-east4-docker.pkg.dev/${GCP_PROJECT}/default-gar`
- Jira Cloud instance at `https://${JIRA_DOMAIN}.atlassian.net` with projects `MDOMO`, `CHALK`, `INFRA`, `FSTR` already created
- `gh` CLI available in CI (bundled in the Docker image)

---

## One-Time Setup

### 1. Jenkins Credentials

Add the following credentials in Jenkins → Manage Jenkins → Credentials:

| Credential ID | Type | Description |
|---|---|---|
| `claude-code-oauth-token` | Secret text | Claude Code OAuth token |
| `github-app` | GitHub App | GitHub App for repo access (provides `GH_TOKEN` at runtime) |
| `jenkins-api-key` | Secret text | Jenkins API key for triggering parameterized jobs |
| `jira_api_key` | Secret text | Jira API token (generate at id.atlassian.com) |
| `jenkins-gke-sa` | Secret file | GCP service account JSON key with `roles/artifactregistry.writer` (build jobs only) |

### 2. Build and Push the Docker Image

The Majordomo Jenkins job runs inside a container defined in `docker/majordomo-runner/Dockerfile`. Build and push it before running Majordomo for the first time, and any time the Dockerfile or `majordomo/requirements.txt` changes.

Create a Jenkins pipeline job pointing to `docker/majordomo-runner/Jenkinsfile` in this repo, then trigger it manually.

Alternatively, build locally:

```bash
# From repo root
docker build -f docker/majordomo-runner/Dockerfile -t majordomo-runner:local .

# Push to GAR (requires gcloud auth)
GAR_REPO="us-east4-docker.pkg.dev/${GCP_PROJECT}/default-gar"
docker tag majordomo-runner:local ${GAR_REPO}/majordomo-runner:latest
docker push ${GAR_REPO}/majordomo-runner:latest
```

### 3. Create Jenkins Pipeline Jobs

| Job name | Jenkinsfile path | Trigger |
|---|---|---|
| `majordomo` | `Jenkinsfile` | Manual (Stage 1); cron after Stage 5 |
| `majordomo-build-runner` | `docker/majordomo-runner/Jenkinsfile` | Weekly cron (Sundays ~2 AM); manual as needed |
| `majordomo-planning-agent` | `majordomo/jenkins/planning-agent/Jenkinsfile` | Triggered by Majordomo (Stage 3) |
| `majordomo-worker` | `majordomo/jenkins/worker/Jenkinsfile` | Triggered by Majordomo (Stage 2) |

The planning-agent and worker Jenkinsfiles do not exist yet — they will be created in Stages 2 and 3.

For each job: New Item → Pipeline → select "Pipeline script from SCM" → point to this repo and the Jenkinsfile path listed above.

---

## Configuration

`majordomo/config.yaml` is the central config file read by Majordomo on every run.

```yaml
# GitHub users whose issues Majordomo will process
allowed_gh_users:
  - wcjordan

# Repos tracked by Majordomo and their Jira project keys
projects:
  - repo: minordomo
    jira_key: MDOMO
  ...

# Stage 5: Schedule gating (not yet enforced)
schedule:
  allowed_days: [Mon, Tue, Wed, Thu, Fri]
  allowed_hours: ["00:00-08:00", "18:00-23:59"]
  weekend_override: false

# Stage 5: Usage limits (not yet enforced)
usage:
  weekly_threshold_pct: 50
```

To add a new repo: add an entry to `projects` and create the corresponding Jira project.

---

## Agent Permissions

`majordomo/agent-settings.json` is the Claude Code permissions template deployed into every agent container. It allows broad tool use with a targeted deny list (no force pushes, no sudo, no cloud metadata access). It is **not** the settings file for local development.

`hooks/pre-bash-guard.sh` is a secondary safety hook that provides defence-in-depth for patterns the deny list's glob matching may miss. It is referenced by `agent-settings.json` and runs before every Bash tool invocation inside an agent container.

---

## Local Development

Normal `claude` / Claude Code usage in this repo uses `.claude/settings.local.json`, not `majordomo/agent-settings.json`. The agent settings are only deployed inside Jenkins job containers.

To test the pre-bash-guard hook locally:

```bash
# Should block (exit 1):
echo '{"tool_input": {"command": "git push --force origin main"}}' | hooks/pre-bash-guard.sh

# Should allow (exit 0):
echo '{"tool_input": {"command": "git push origin main"}}' | hooks/pre-bash-guard.sh
```
