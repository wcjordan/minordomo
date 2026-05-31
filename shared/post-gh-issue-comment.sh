#!/usr/bin/env bash
# Posts a comment to a GitHub issue.
# Usage: post-gh-issue-comment.sh <gh_issue_number> <repo> <comment_body>

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: post-gh-issue-comment.sh <gh_issue_number> <repo> <comment_body>" >&2
    exit 2
fi

gh_issue_number="$1"
repo="$2"
comment_body="$3"

gh issue comment "${gh_issue_number}" --repo "wcjordan/${repo}" --body "${comment_body}" \
    || { echo "Failed to post comment to issue ${gh_issue_number}" >&2; exit 1; }
