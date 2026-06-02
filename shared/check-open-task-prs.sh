#!/usr/bin/env bash
# Check whether any open task/ PRs are targeting a feature branch.
# Usage: check-open-task-prs.sh <repo> <epic_key>
# Exits 0 and outputs the head branch name if any open task PRs target feature/<epic_key>; exits 1 with empty output if none; exits 2 on wrong argument count.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: check-open-task-prs.sh <repo> <epic_key>" >&2
    exit 2
fi

repo="$1"
epic_key="$2"

gh pr list \
    --repo "wcjordan/${repo}" \
    --base "feature/${epic_key}" \
    --state open \
    --json headRefName \
| python3 -c "
import json, sys
arr = json.load(sys.stdin)
for pr in arr:
    if pr['headRefName'].startswith('task/'):
        print(pr['headRefName'])
        sys.exit(0)
sys.exit(1)
"
