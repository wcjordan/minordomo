#!/usr/bin/env bash
# Shared workspace setup for majordomo agents.
# Source from an agent-specific wrapper — do not source directly.
# Usage: source shared/setup-workspace.sh <mode>
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
cfg = yaml.safe_load(open('shared/config.yaml'))
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
        git checkout -b "${FEATURE_BRANCH}" "origin/${BASE_BRANCH}"
        git push -u origin "${FEATURE_BRANCH}"
    fi
else
    git checkout "${FEATURE_BRANCH}"

    # Detect if this is the first implementation task of the Epic.
    # If so, merge origin/${BASE_BRANCH} into the feature branch before creating the task branch.
    JQL="parent = ${EPIC_KEY} AND issuetype = Task AND summary !~ \"Plan:\""
    JQL_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$JQL")
    SIBLINGS_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
        -H "Accept: application/json" \
        "${JIRA_URL}/rest/api/3/search/jql?jql=${JQL_ENCODED}&fields=customfield_10019&maxResults=100")
    SIBLINGS_HTTP_CODE=$(echo "$SIBLINGS_RESPONSE" | tail -1)
    SIBLINGS_JSON=$(echo "$SIBLINGS_RESPONSE" | sed '$d')
    if [[ "$SIBLINGS_HTTP_CODE" != "200" ]]; then
        echo "WARNING: Jira sibling query failed (HTTP ${SIBLINGS_HTTP_CODE}): ${SIBLINGS_JSON}" >&2
        echo "Skipping base-branch merge — grant the service account Browse Projects permission to enable this." >&2
        IS_FIRST_TASK="unknown"
    else
        IS_FIRST_TASK=$(echo "$SIBLINGS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
issues = data.get('issues', [])
if not issues:
    sys.exit('No implementation siblings found for Epic ${EPIC_KEY}')
sorted_issues = sorted(issues, key=lambda x: x['fields'].get('customfield_10019', ''))
print('yes' if sorted_issues[0]['key'] == '${JIRA_TASK_ID}' else 'no')
")
    fi

    if [[ "$IS_FIRST_TASK" == "yes" ]]; then
        git fetch origin "${BASE_BRANCH}"
        git merge "origin/${BASE_BRANCH}" -m "chore: merge ${BASE_BRANCH} into ${FEATURE_BRANCH} before first implementation stage"
        git push origin "${FEATURE_BRANCH}"
    fi
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

# Initialize the beads workspace against the central Dolt server.
# metadata.json is committed but the Dolt DB is not — bd init --server connects and pulls it.
bd init --server --server-user "${BEADS_DOLT_SERVER_USER}"
bd dolt show
