#!/usr/bin/env bash
# Transition a Jira issue to a named status.
# Usage: jira-transition.sh <issue_key> <status_name>
# Reads JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN from environment.
# Exits non-zero with a descriptive error if the transition is not found or any
# curl call fails. Uses -f so HTTP 4xx/5xx errors also cause non-zero exit.

set -euo pipefail

issue_key="${1:?Usage: jira-transition.sh <issue_key> <status_name>}"
status_name="${2:?Usage: jira-transition.sh <issue_key> <status_name>}"

: "${JIRA_URL:?JIRA_URL must be set}"
: "${JIRA_EMAIL:?JIRA_EMAIL must be set}"
: "${JIRA_API_TOKEN:?JIRA_API_TOKEN must be set}"

TRANSITIONS_JSON=$(curl -sf -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    "${JIRA_URL}/rest/api/3/issue/${issue_key}/transitions") || {
    echo "ERROR: Failed to fetch transitions for ${issue_key}" >&2
    exit 1
}

TRANSITION_ID=$(echo "$TRANSITIONS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('transitions', []):
    if t.get('to', {}).get('name') == sys.argv[1]:
        print(t['id'])
        sys.exit(0)
print('NOT_FOUND', file=sys.stderr)
sys.exit(1)
" "$status_name") || {
    echo "ERROR: Transition to '${status_name}' not found for ${issue_key}" >&2
    exit 1
}

curl -sf -X POST -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${JIRA_URL}/rest/api/3/issue/${issue_key}/transitions" \
    -d "{\"transition\": {\"id\": \"${TRANSITION_ID}\"}}" || {
    echo "ERROR: Failed to post transition '${status_name}' for ${issue_key}" >&2
    exit 1
}
