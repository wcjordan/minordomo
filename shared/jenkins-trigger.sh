#!/usr/bin/env bash
# Trigger a Jenkins job via buildWithParameters.
# Usage: jenkins-trigger.sh <job-name> <beads-task-id>
# Reads JENKINS_USERNAME, JENKINS_API_KEY, ROOT_DOMAIN, BASE_BRANCH from environment.
# Exits non-zero with a descriptive error if the HTTP response is not 201 or any curl call fails.

set -euo pipefail

job_name="${1:?Usage: jenkins-trigger.sh <job-name> <beads-task-id>}"
beads_task_id="${2:?Usage: jenkins-trigger.sh <job-name> <beads-task-id>}"

: "${JENKINS_USERNAME:?JENKINS_USERNAME must be set}"
: "${JENKINS_API_KEY:?JENKINS_API_KEY must be set}"
: "${ROOT_DOMAIN:?ROOT_DOMAIN must be set}"
: "${BASE_BRANCH:?BASE_BRANCH must be set}"

url="http://jenkins.${ROOT_DOMAIN}/job/${job_name}/job/${BASE_BRANCH}/buildWithParameters?BEADS_TASK_ID=${beads_task_id}"

http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -u "${JENKINS_USERNAME}:${JENKINS_API_KEY}" \
    "${url}") || {
    echo "ERROR: curl failed when triggering Jenkins job '${job_name}' with task '${beads_task_id}'" >&2
    exit 1
}

if [ "${http_code}" != "201" ]; then
    echo "ERROR: Jenkins job trigger returned HTTP ${http_code} (expected 201) for job '${job_name}' task '${beads_task_id}'" >&2
    exit 1
fi
