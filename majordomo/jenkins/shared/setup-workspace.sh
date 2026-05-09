#!/usr/bin/env bash
# Shared workspace setup for majordomo agents.
# Source from an agent-specific wrapper — do not source directly.
# Usage: source majordomo/jenkins/shared/setup-workspace.sh <mode>
#   worker   — feature branch must exist; always creates a fresh task branch
#   planning — creates feature branch if missing; resumes task branch if it exists
#
# Requires: JIRA_TASK_ID, JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, GH_TOKEN, BASE_BRANCH env vars
# Exports:  REPO, EPIC_KEY, FEATURE_BRANCH

set -euo pipefail

MODE="${1:?Usage: source setup-workspace.sh <worker|planning>}"

# Derive REPO from the Jira project key via config.yaml
PROJECT_KEY="${JIRA_TASK_ID%%-*}"
export REPO
REPO=$(python3 -c "
import yaml, sys
cfg = yaml.safe_load(open('majordomo/config.yaml'))
matches = [p['repo'] for p in cfg['projects'] if p['jira_key'] == '$PROJECT_KEY']
if not matches:
    sys.exit('No repo found for project key $PROJECT_KEY')
print(matches[0])
")

# Derive EPIC_KEY and FEATURE_BRANCH from the task's parent Epic via Jira REST API
JIRA_RESPONSE=$(curl -s -f \
    -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Accept: application/json" \
    "${JIRA_URL}/rest/api/3/issue/${JIRA_TASK_ID}?fields=parent")

export EPIC_KEY
EPIC_KEY=$(echo "$JIRA_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
parent = data.get('fields', {}).get('parent', {})
if not parent:
    sys.exit('No parent Epic found on task $JIRA_TASK_ID')
print(parent['key'])
")
export FEATURE_BRANCH="feature/${EPIC_KEY}"

echo "Derived REPO=${REPO} EPIC_KEY=${EPIC_KEY} FEATURE_BRANCH=${FEATURE_BRANCH}"

# Wire up git credential helper so plain git commands can auth via GH_TOKEN.
gh auth setup-git

# Clone the target repo and cd into it.
gh repo clone "wcjordan/${REPO}" "${REPO}"
cd "${REPO}"

# Feature branch: planning creates it from main if missing; worker assumes it exists.
if [[ "$MODE" == "planning" ]]; then
    if git ls-remote --exit-code origin "${FEATURE_BRANCH}" > /dev/null 2>&1; then
        git checkout "${FEATURE_BRANCH}"
    else
        git checkout -b "${FEATURE_BRANCH}" "${BASE_BRANCH}"
        git push -u origin "${FEATURE_BRANCH}"
    fi
else
    git checkout "${FEATURE_BRANCH}"
fi

# Task branch: planning resumes an existing branch because the Needs Input cycle re-triggers
# it on the same task (research notes from the first run must survive). Workers have no
# re-run cycle yet — each Implementation Task is expected to complete in one shot — so
# always creating fresh keeps things simple. If worker re-runs are added later (Stage 6+),
# resume logic will need to be introduced here.
if [[ "$MODE" == "planning" ]]; then
    if git ls-remote --exit-code origin "task/${JIRA_TASK_ID}" > /dev/null 2>&1; then
        git checkout "task/${JIRA_TASK_ID}"
        git pull
    else
        git checkout -b "task/${JIRA_TASK_ID}"
    fi
else
    git checkout -b "task/${JIRA_TASK_ID}"
fi
