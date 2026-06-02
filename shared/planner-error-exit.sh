#!/usr/bin/env bash
# Encapsulates the deterministic steps needed on any planning agent error exit.
# 1. Post a GH comment (best-effort — failure is logged, execution continues)
# 2. Reset the beads task status back to open (required — failure causes non-zero exit)
# Usage: planner-error-exit.sh <beads_task_id> <repo> <gh_issue_number> <comment_body>
# Pass "" for gh_issue_number to skip the GH comment step.

set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Usage: planner-error-exit.sh <beads_task_id> <repo> <gh_issue_number> <comment_body>" >&2
    exit 2
fi

beads_task_id="$1"
repo="$2"
gh_issue_number="$3"
comment_body="$4"

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [ -n "${gh_issue_number}" ]; then
    "${SCRIPT_DIR}/post-gh-issue-comment.sh" "${gh_issue_number}" "${repo}" "${comment_body}" \
        || { echo "Failed to post GH comment to issue ${gh_issue_number}" >&2; }
fi

"${SCRIPT_DIR}/beads-write.sh" update "${beads_task_id}" --status open \
    || { echo "Failed to reset beads task ${beads_task_id} to open" >&2; exit 1; }
