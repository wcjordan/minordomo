#!/usr/bin/env bash
# Derive Story bead ID (EPIC_KEY), GH_ISSUE_NUMBER, and REPO from a beads task ID.
# Usage: shared/get-story-key.sh <beads_task_id>
# Output (stdout): Story bead ID on line 1, GH_ISSUE_NUMBER on line 2, repo name on line 3
# Exits 1 with a message to stderr on failure.

set -euo pipefail

BEADS_TASK_ID="${1:?Usage: get-story-key.sh <beads_task_id>}"

TASK_JSON=$(bd show "${BEADS_TASK_ID}" --json 2>/dev/null) || {
    echo "ERROR: Task ${BEADS_TASK_ID} not found" >&2
    exit 1
}

if [ -z "$TASK_JSON" ] || [ "$TASK_JSON" = "[]" ]; then
    echo "ERROR: Task ${BEADS_TASK_ID} not found" >&2
    exit 1
fi

TASK_TITLE=$(echo "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('title') or '')")
PARENT_ID=$(echo "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('parent') or '')")

STORY_BEAD_ID=""
STORY_DESC=""

if [[ "$TASK_TITLE" == Story:* ]]; then
    STORY_BEAD_ID="${BEADS_TASK_ID}"
    STORY_DESC=$(echo "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('description') or '')")
elif [ -n "$PARENT_ID" ]; then
    PARENT_JSON=$(bd show "$PARENT_ID" --json 2>/dev/null) || {
        echo "ERROR: Parent task ${PARENT_ID} not found" >&2
        exit 1
    }
    PARENT_TITLE=$(echo "$PARENT_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('title') or '')")
    if [[ "$PARENT_TITLE" == Story:* ]]; then
        STORY_BEAD_ID="${PARENT_ID}"
        STORY_DESC=$(echo "$PARENT_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('description') or '')")
    fi
fi

if [ -z "$STORY_BEAD_ID" ]; then
    echo "ERROR: No Story bead found for task ${BEADS_TASK_ID}: neither the task nor its parent has a title starting with 'Story:'" >&2
    exit 1
fi

GH_ISSUE_URL=$(echo "$STORY_DESC" | grep -Eo 'https://github\.com/[^[:space:]]+/issues/[0-9]+' | head -1 || true)

if [ -z "$GH_ISSUE_URL" ]; then
    echo "ERROR: No GH Issue URL found in Story bead ${STORY_BEAD_ID} description" >&2
    exit 1
fi

GH_ISSUE_NUMBER=$(echo "$GH_ISSUE_URL" | grep -Eo '[0-9]+$')
REPO_NAME=$(echo "$GH_ISSUE_URL" | sed 's|https://github\.com/[^/]*/||; s|/issues.*||')

echo "${STORY_BEAD_ID}"
echo "${GH_ISSUE_NUMBER}"
echo "${REPO_NAME}"
