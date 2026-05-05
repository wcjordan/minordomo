#!/usr/bin/env bash
# Derives REPO and FEATURE_BRANCH from JIRA_TASK_ID, clones the target repo,
# and creates the task branch. Source this script — do not execute it directly.
# After sourcing, the shell's working directory is the root of the cloned repo.
#
# Requires: JIRA_TASK_ID, DOMAIN_ROOT, JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, GH_TOKEN env vars
# Exports:  REPO, FEATURE_BRANCH

set -euo pipefail

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

# Derive FEATURE_BRANCH from the task's parent Epic key via Jira REST API
JIRA_RESPONSE=$(curl -s -f \
    -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Accept: application/json" \
    "${JIRA_URL}/rest/api/3/issue/${JIRA_TASK_ID}?fields=parent")

EPIC_KEY=$(echo "$JIRA_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
parent = data.get('fields', {}).get('parent', {})
if not parent:
    sys.exit('No parent Epic found on task $JIRA_TASK_ID')
print(parent['key'])
")
export FEATURE_BRANCH="feature/${EPIC_KEY}"

echo "Derived REPO=${REPO} FEATURE_BRANCH=${FEATURE_BRANCH}"

# Wire up git credential helper so plain git commands can auth via GH_TOKEN.
gh auth setup-git

# Clone the target repo, create the task branch, and cd into the repo.
# After this point the working directory is the repo root.
gh repo clone "wcjordan/${REPO}" "${REPO}"
cd "${REPO}"
git checkout "${FEATURE_BRANCH}"
git checkout -b "task/${JIRA_TASK_ID}"
git push -u origin "task/${JIRA_TASK_ID}"
