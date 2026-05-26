# Research: Extract Jenkins Job Trigger to shared/jenkins-trigger.sh

## Problem

The `majordomo/system-prompt.md` contains two identical inline Jenkins curl commands:

1. **Step 5** (planning agent trigger, ~line 210-211):
   ```bash
   curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
     "http://jenkins.${ROOT_DOMAIN}/job/minordomo-plan/job/${BASE_BRANCH}/buildWithParameters?BEADS_TASK_ID=<beads_plan_id>"
   ```

2. **Step 8** (worker trigger, ~line 351-352):
   ```bash
   curl -X POST -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
     "http://jenkins.${ROOT_DOMAIN}/job/minordomo-step/job/${BASE_BRANCH}/buildWithParameters?BEADS_TASK_ID=<beads_impl_id>"
   ```

## Proposed Solution

Create `shared/jenkins-trigger.sh <job-name> <beads-task-id>` that centralises:
- URL construction
- HTTP basic auth with `JENKINS_USERNAME` / `JENKINS_API_KEY`
- HTTP 201 response validation
- Non-zero exit on failure

## Existing Patterns (from similar shared scripts)

### `shared/jira-transition.sh`
- `set -euo pipefail`
- Validate env vars: `${VAR:?message}`
- Use `curl -sf` (silent + fail on HTTP 4xx/5xx)
- Descriptive stderr error messages on failure

### `shared/check-pr-merged.sh`
- Same shell conventions
- Args validated with positional checks

### Test patterns (`test/bats/jira-transition.bats`)
- `setup()` creates a `TMP_DIR` added to `PATH` containing a fake `curl`
- Tests: happy path, non-zero exits for missing env vars, HTTP failure

## Files to Modify

| File | Change |
|------|--------|
| `shared/jenkins-trigger.sh` | New script |
| `test/bats/jenkins-trigger.bats` | New bats test file |
| `majordomo/system-prompt.md` | Replace inline curl (×2) with `shared/jenkins-trigger.sh` |
| `CLAUDE.md` | Update "Jenkins Job Trigger URLs" section to show the script |

## Jenkins HTTP Response Notes

Jenkins returns HTTP 201 (Created) for a successful `buildWithParameters` POST.
The script should check for this with `curl -w "%{http_code}"` or use `-f` which
fails on 4xx/5xx but not on 201 vs 200. Using `-f` is sufficient since 201 is a
2xx success and curl `-f` only fails on 4xx+.

Actually, `-sf` with curl treats any 2xx as success, so `-sf` is sufficient to
detect failure. The GH issue says "Validates HTTP 201 response" — to be precise,
we can use `-w "%{http_code}"` and check it equals 201. But the simplest correct
approach matching the codebase pattern is `-sf` (fails on 4xx+).

For strict 201 checking: use `--write-out '%{http_code}'` and compare. This is
slightly more robust since Jenkins could return a different 2xx for an error condition.
Given the GH issue explicitly calls for 201 validation, implement strict checking.
