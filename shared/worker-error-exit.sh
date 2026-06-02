#!/usr/bin/env bash
# Encapsulates the 3-step error exit sequence for worker agents (non-needs-input path):
# 1. Get GH issue number via get-story-key.sh (best-effort)
# 2. Post GH comment via post-gh-issue-comment.sh (best-effort; skipped if step 1 failed)
# 3. Reset beads task to open via beads-write.sh (required; failure exits non-zero)
# Usage: worker-error-exit.sh <beads_task_id> <repo> <comment_body>

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: worker-error-exit.sh <beads_task_id> <repo> <comment_body>" >&2
    exit 2
fi

beads_task_id="$1"
repo="$2"
comment_body="$3"

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Step 1: Get GH issue number (best-effort; stderr from get-story-key.sh passes through)
GH_ISSUE_NUMBER=""
if STORY_OUTPUT=$("${SCRIPT_DIR}/get-story-key.sh" "$beads_task_id" "$repo"); then
    GH_ISSUE_NUMBER=$(echo "$STORY_OUTPUT" | sed -n '2p')
else
    echo "ERROR: get-story-key.sh failed for task ${beads_task_id}; skipping GH comment" >&2
fi

# Step 2: Apply needs-input label and post GH comment (best-effort; skipped if GH issue number unavailable)
if [ -n "$GH_ISSUE_NUMBER" ]; then
    gh issue edit "${GH_ISSUE_NUMBER}" --repo "wcjordan/${repo}" --add-label needs-input \
        || echo "ERROR: Failed to apply needs-input label to issue ${GH_ISSUE_NUMBER}" >&2
    "${SCRIPT_DIR}/post-gh-issue-comment.sh" "$GH_ISSUE_NUMBER" "$repo" "$comment_body" \
        || echo "ERROR: Failed to post GH comment to issue ${GH_ISSUE_NUMBER}" >&2
fi

# Step 3: Reset beads task (required)
"${SCRIPT_DIR}/beads-write.sh" update "$beads_task_id" --status open \
    || { echo "ERROR: Failed to reset beads task ${beads_task_id} to open" >&2; exit 1; }
