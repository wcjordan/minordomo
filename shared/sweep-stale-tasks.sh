#!/usr/bin/env bash
# Sweeps stale in-progress beads tasks back to open.
# A task is stale if started_at is more than 12 hours ago and it has no open PR.
# Usage: shared/sweep-stale-tasks.sh
# Exits 0 always (partial success is better than aborting the sweep).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: List all in-progress tasks.
IN_PROGRESS_JSON=$(bd list --status=in_progress --json 2>/dev/null) || IN_PROGRESS_JSON="[]"

if [ -z "$IN_PROGRESS_JSON" ] || [ "$IN_PROGRESS_JSON" = "[]" ]; then
    echo "Swept 0 stale task(s) to open (0 comment errors)."
    exit 0
fi

# Step 2: Filter to tasks started more than 12 hours ago.
STALE_JSON=$(echo "$IN_PROGRESS_JSON" | python3 -c "
import json, sys
from datetime import datetime

tasks = json.load(sys.stdin)
now = datetime.utcnow()
stale = []
for task in tasks:
    started_at = task.get('started_at')
    if not started_at:
        continue
    try:
        started_dt = datetime.fromisoformat(started_at.replace('Z', '+00:00')).replace(tzinfo=None)
        age_hours = (now - started_dt).total_seconds() / 3600
        if age_hours > 12:
            stale.append(task)
    except (ValueError, AttributeError):
        pass
print(json.dumps(stale))
") || STALE_JSON="[]"

TASK_IDS=$(echo "$STALE_JSON" | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
for task in tasks:
    print(task['id'])
") || TASK_IDS=""

swept_count=0
comment_errors=0

while IFS= read -r task_id; do
    [ -z "$task_id" ] && continue

    # Step 3: Derive repo for this task by longest-match against config repos.
    repo=$(python3 -c "
import yaml, sys
task_id, config_path = sys.argv[1], sys.argv[2]
cfg = yaml.safe_load(open(config_path))
repos = sorted([p['repo'] for p in cfg['projects']], key=len, reverse=True)
for repo in repos:
    if task_id.startswith(repo + '-'):
        print(repo)
        sys.exit(0)
sys.exit(1)
" "$task_id" "${SCRIPT_DIR}/config.yaml" 2>/dev/null) || {
        echo "ERROR: Could not derive repo for task ${task_id}" >&2
        continue
    }

    # Step 4: Skip tasks that have an open PR — they are in review, not orphaned.
    open_pr_count=$(gh pr list \
        --repo "wcjordan/${repo}" \
        --head "task/${task_id}" \
        --state open \
        --json number 2>/dev/null \
        | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null) || open_pr_count=0

    if [ "${open_pr_count}" -gt 0 ]; then
        continue
    fi

    # Step 5a: Post comment on GH issue before resetting; failure does not block reset.
    utc_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    comment_body="Sweep job reset this task to \`open\` at \`${utc_ts}\`. It had been \`in_progress\` for more than 12 hours — likely due to a Jenkins container crash. Majordomo will re-queue it on the next run."

    epic_output=$("${SCRIPT_DIR}/get-epic-key.sh" "$task_id" "$repo" 2>/dev/null) || {
        echo "ERROR: Failed to get GH issue for task ${task_id}" >&2
        comment_errors=$((comment_errors + 1))
        epic_output=""
    }

    if [ -n "$epic_output" ]; then
        gh_issue_number=$(echo "$epic_output" | sed -n '2p')
        gh issue comment "$gh_issue_number" \
            --repo "wcjordan/${repo}" \
            --body "$comment_body" 2>/dev/null || {
            echo "ERROR: Failed to post comment on GH issue ${gh_issue_number} for task ${task_id}" >&2
            comment_errors=$((comment_errors + 1))
        }
    fi

    # Step 5b: Reset task to open.
    if "${SCRIPT_DIR}/beads-write.sh" update "$task_id" --status open 2>/dev/null; then
        swept_count=$((swept_count + 1))
    else
        echo "ERROR: Failed to reset task ${task_id} to open" >&2
    fi

done <<< "$TASK_IDS"

echo "Swept ${swept_count} stale task(s) to open (${comment_errors} comment errors)."
exit 0
