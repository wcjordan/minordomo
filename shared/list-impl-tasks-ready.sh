#!/usr/bin/env bash
# Output a JSON array of ready implementation tasks (excludes Plan: and Story: tasks).
# Usage: shared/list-impl-tasks-ready.sh

set -euo pipefail

bd ready --json | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
impl = [t for t in tasks if not t.get('title', '').startswith(('Plan:', 'Story:'))]
print(json.dumps(impl))
"
