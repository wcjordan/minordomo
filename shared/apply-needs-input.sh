#!/usr/bin/env bash
# Encapsulates the three-step needs-input protocol:
# 1. Apply the needs-input label to a GitHub issue
# 2. Post a comment to that issue
# 3. Reset the beads task status back to open
# Usage: apply-needs-input.sh <repo> <issue_number> <beads_task_id> <comment_body>

set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Usage: apply-needs-input.sh <repo> <issue_number> <beads_task_id> <comment_body>" >&2
    exit 2
fi

repo="$1"
issue_number="$2"
beads_task_id="$3"
comment_body="$4"

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

gh issue edit "${issue_number}" --repo "wcjordan/${repo}" --add-label needs-input \
    || { echo "Failed to apply needs-input label to issue ${issue_number}" >&2; exit 1; }

gh issue comment "${issue_number}" --repo "wcjordan/${repo}" --body "${comment_body}" \
    || { echo "Failed to post comment to issue ${issue_number}" >&2; exit 1; }

"${SCRIPT_DIR}/beads-write.sh" update "${beads_task_id}" --status open \
    || { echo "Failed to reset beads task ${beads_task_id} to open" >&2; exit 1; }
