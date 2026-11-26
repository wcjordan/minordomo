#!/usr/bin/env bash
# Output a JSON array of ready implementation tasks (excludes Plan: and Story: tasks).
# Only tasks with a parent (i.e. Stage tasks under a Story bead) are included:
# parentless tasks (e.g. ad-hoc follow-up beads) have no Story to derive a repo,
# GH issue, or feature branch from, so the worker pipeline cannot run them.
# Usage: shared/list-impl-tasks-ready.sh

set -euo pipefail

bd ready --json | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
impl = [
    t for t in tasks
    if t.get('parent') and not t.get('title', '').startswith(('Plan:', 'Story:'))
]
print(json.dumps(impl))
"
