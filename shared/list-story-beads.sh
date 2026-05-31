#!/usr/bin/env bash
# Output a JSON array of open Story beads.
# Usage: shared/list-story-beads.sh

set -euo pipefail

bd list --json | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
print(json.dumps([t for t in tasks if t.get('title', '').startswith('Story:')]))
"
