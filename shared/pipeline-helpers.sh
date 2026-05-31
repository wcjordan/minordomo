#!/usr/bin/env bash
# Shared helper functions for pipeline agents.
# Source this file early in your run: source shared/pipeline-helpers.sh
# This file defines functions only — no top-level commands are executed.

# Look up a beads task ID by exact title, searching both open and in_progress.
# Usage: beads_task_id_by_title <title>
# Prints the task ID to stdout, or nothing if not found. Exits 0 in either case.
beads_task_id_by_title() {
    local title="$1"
    { bd list --json; bd list --status=in_progress --json; } \
        | python3 -c "
import json, sys

title = sys.argv[1]
seen = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        tasks = json.loads(line)
    except json.JSONDecodeError:
        continue
    for t in tasks:
        tid = t.get('id', '')
        if tid in seen:
            continue
        seen.add(tid)
        if t.get('title') == title:
            print(tid)
            sys.exit(0)
" "$title"
}

# Check whether a GitHub issue carries the needs-input label.
# Usage: has_needs_input <repo> <issue_number>
# Returns exit code 0 if label is present, 1 if not.
has_needs_input() {
    local repo="$1"
    local issue_number="$2"
    gh issue view "$issue_number" --repo "wcjordan/$repo" --json labels \
        | python3 -c "
import json, sys
labels = json.load(sys.stdin).get('labels', [])
sys.exit(0 if any(l.get('name') == 'needs-input' for l in labels) else 1)
"
}

# Extract the first P0–P4 priority label from a JSON labels array.
# Usage: extract_priority <labels_json>
# Accepts the JSON array from `gh issue view --json labels --jq '.labels'`.
# Prints the matched label (e.g. "P1") or "P2" as the default if none matched.
extract_priority() {
    local labels_json="$1"
    python3 -c "
import json, sys
try:
    labels = json.loads(sys.argv[1])
except (json.JSONDecodeError, ValueError):
    labels = []
for label in labels:
    name = label.get('name', '')
    if name in ('P0', 'P1', 'P2', 'P3', 'P4'):
        print(name)
        sys.exit(0)
print('P2')
" "$labels_json"
}
