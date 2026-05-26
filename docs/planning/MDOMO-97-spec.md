# Plan: Extract Jenkins Job Trigger to shared/jenkins-trigger.sh

**Epic:** MDOMO-97  
**GH Issue:** https://github.com/wcjordan/minordomo/issues/143

## Overview

The Jenkins `buildWithParameters` curl command appears twice in `majordomo/system-prompt.md` — once for the planning agent (Step 5) and once for the worker (Step 8/9). This spec extracts that logic into `shared/jenkins-trigger.sh`, following the same pattern as `shared/jira-transition.sh` and `shared/check-pr-merged.sh`.

---

## Stage 1: Create shared/jenkins-trigger.sh with tests

### Description

Create `shared/jenkins-trigger.sh <job-name> <beads-task-id>` that:
- Reads `JENKINS_USERNAME`, `JENKINS_API_KEY`, `ROOT_DOMAIN`, `BASE_BRANCH` from environment
- Validates all four env vars are present, exits non-zero with a message if any are missing
- Constructs the URL: `http://jenkins.${ROOT_DOMAIN}/job/<job-name>/job/${BASE_BRANCH}/buildWithParameters?BEADS_TASK_ID=<beads-task-id>`
- POSTs to that URL with HTTP basic auth
- Validates that the HTTP response code is exactly 201; exits non-zero with a descriptive error if not
- Exits 0 on success

Create `test/bats/jenkins-trigger.bats` with tests that cover:
- Happy path: curl returns 201 → exit 0
- Non-201 response (e.g. 404) → exit non-zero
- curl itself fails (non-zero exit) → exit non-zero
- Missing `JENKINS_USERNAME` → exit non-zero
- Missing `JENKINS_API_KEY` → exit non-zero
- Missing `ROOT_DOMAIN` → exit non-zero
- Missing `BASE_BRANCH` → exit non-zero

### Acceptance Criteria
- `shared/jenkins-trigger.sh` exists and is executable (`chmod +x`)
- Script uses `set -euo pipefail`
- All four required env vars are validated at startup
- Successful 201 response exits 0
- Non-201 HTTP response exits non-zero with an error message on stderr
- `test/bats/jenkins-trigger.bats` exists with tests for all cases above
- `make test` passes

---

## Stage 2: Update majordomo system prompt and documentation

### Description

Replace both inline Jenkins curl commands in `majordomo/system-prompt.md` with calls to the new script. Update `CLAUDE.md` to reference the script in the "Jenkins Job Trigger URLs" section.

**In `majordomo/system-prompt.md`:**

Step 5 (planning agent trigger) — replace:
```bash
curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
  "http://jenkins.${ROOT_DOMAIN}/job/minordomo-plan/job/${BASE_BRANCH}/buildWithParameters?BEADS_TASK_ID=<beads_plan_id>"
```
with:
```bash
shared/jenkins-trigger.sh minordomo-plan "<beads_plan_id>"
```

Step 8/9 (worker trigger) — replace:
```bash
curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
  "http://jenkins.${ROOT_DOMAIN}/job/minordomo-step/job/${BASE_BRANCH}/buildWithParameters?BEADS_TASK_ID=<beads_impl_id>"
```
with:
```bash
shared/jenkins-trigger.sh minordomo-step "<beads_impl_id>"
```

Also remove or update the header-level inline authentication instructions for Jenkins (lines ~19-21 in the system prompt) that describe how to authenticate Jenkins calls manually, since that is now encapsulated in the script.

**In `CLAUDE.md`** (both the repo-level and minordomo subdirectory copies):

Update the "Jenkins Job Trigger URLs" section to show the new script interface alongside or instead of the raw curl, so contributors know to use `shared/jenkins-trigger.sh` when adding new job triggers.

### Acceptance Criteria
- `majordomo/system-prompt.md` contains no inline `buildWithParameters` curl commands
- Both trigger locations use `shared/jenkins-trigger.sh <job> <beads-task-id>`
- `CLAUDE.md` "Jenkins Job Trigger URLs" section documents the new script usage
- `make test` passes (shellcheck on system-prompt.md bash blocks is not run, but bats pass)
