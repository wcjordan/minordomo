#!/usr/bin/env bash
# Derive EPIC_KEY and GH_ISSUE_NUMBER from a beads task ID.
# Usage: shared/get-epic-key.sh <beads_task_id> <repo>
# Output (stdout): EPIC_KEY on line 1, GH_ISSUE_NUMBER on line 2
# Exits 1 with a message to stderr on failure.

set -euo pipefail

BEADS_TASK_ID="${1:?Usage: get-epic-key.sh <beads_task_id> <repo>}"
REPO="${2:?Usage: get-epic-key.sh <beads_task_id> <repo>}"

TASK_JSON=$(bd show "${BEADS_TASK_ID}" --json 2>/dev/null) || {
    echo "ERROR: Task ${BEADS_TASK_ID} not found" >&2
    exit 1
}

if [ -z "$TASK_JSON" ] || [ "$TASK_JSON" = "[]" ]; then
    echo "ERROR: Task ${BEADS_TASK_ID} not found" >&2
    exit 1
fi

TASK_DESC=$(echo "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('description') or '')")
PARENT_ID=$(echo "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('parent') or '')")

GH_ISSUE_URL=$(echo "$TASK_DESC" | grep -Eo 'https://github\.com/[^[:space:]]+/issues/[0-9]+' | head -1 || true)
if [ -z "$GH_ISSUE_URL" ] && [ -n "$PARENT_ID" ]; then
    PARENT_DESC=$(bd show "$PARENT_ID" --json | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('description') or '')")
    GH_ISSUE_URL=$(echo "$PARENT_DESC" | grep -Eo 'https://github\.com/[^[:space:]]+/issues/[0-9]+' | head -1 || true)
fi

if [ -z "$GH_ISSUE_URL" ]; then
    echo "ERROR: No GH Issue URL found in beads task ${BEADS_TASK_ID} or its parent" >&2
    exit 1
fi

GH_ISSUE_NUMBER=$(echo "$GH_ISSUE_URL" | grep -Eo '[0-9]+$')

EPIC_KEY=$(gh issue view "$GH_ISSUE_NUMBER" --repo "wcjordan/${REPO}" --json comments \
    | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
for comment in data.get('comments', []):
    m = re.search(r'Jira Epic: ([A-Z]+-[0-9]+)', comment.get('body', ''))
    if m:
        print(m.group(1))
        sys.exit(0)
sys.exit('No Jira Epic comment found in GH issue')
") || {
    echo "ERROR: No 'Jira Epic:' comment found in GH issue ${GH_ISSUE_NUMBER}" >&2
    exit 1
}

echo "${EPIC_KEY}"
echo "${GH_ISSUE_NUMBER}"
