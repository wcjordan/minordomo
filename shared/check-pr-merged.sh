#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: check-pr-merged.sh <repo> <epic_key> <beads_task_id>" >&2
    exit 2
fi

repo="$1"
epic_key="$2"
beads_task_id="$3"

gh pr list \
    --repo "wcjordan/${repo}" \
    --base "feature/${epic_key}" \
    --head "task/${beads_task_id}" \
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
