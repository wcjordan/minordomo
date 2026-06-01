#!/usr/bin/env bash
# Output a JSON array of Plan: beads. Passes all arguments through to `bd list`.
# Usage: shared/list-plan-beads.sh [--status=STATUS]
#   (no args)              → open Plan beads
#   --status=in_progress   → in_progress Plan beads

set -euo pipefail

bd list "$@" --json | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
print(json.dumps([t for t in tasks if t.get('title', '').startswith('Plan:')]))
"
