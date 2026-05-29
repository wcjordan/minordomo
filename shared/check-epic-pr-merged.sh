#!/usr/bin/env bash
# Check whether a feature→main (base_branch) PR has been merged for an epic.
# Usage: check-epic-pr-merged.sh <repo> <base_branch> <epic_key>
# Exits 0 and outputs the merged PR number if one exists; exits 1 with empty output if not.

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: check-epic-pr-merged.sh <repo> <base_branch> <epic_key>" >&2
    exit 2
fi

repo="$1"
base_branch="$2"
epic_key="$3"

gh pr list \
    --repo "wcjordan/${repo}" \
    --base "${base_branch}" \
    --head "feature/${epic_key}" \
    --state merged \
    --json number \
| python3 -c "
import json, sys
arr = json.load(sys.stdin)
if arr:
    print(arr[0]['number'])
    sys.exit(0)
sys.exit(1)
"
