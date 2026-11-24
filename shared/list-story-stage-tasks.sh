#!/usr/bin/env bash
# Given a Story bead ID, output all Stage task IDs one per line, sorted ascending
# by stage number extracted from the title ("Stage N: ...").
# Includes all statuses (open, blocked, in_progress, deferred, closed).
# Usage: shared/list-story-stage-tasks.sh <story-bead-id>

set -euo pipefail

STORY_ID="${1:?Usage: list-story-stage-tasks.sh <story-bead-id>}"

bd list --parent "$STORY_ID" --all --json | python3 -c "
import json, re, sys

tasks = json.load(sys.stdin)
stage_tasks = [t for t in tasks if t.get('title', '').startswith('Stage')]

def stage_num(t):
    m = re.match(r'Stage\s+(\d+)', t.get('title', ''))
    return int(m.group(1)) if m else 999

stage_tasks.sort(key=stage_num)
for t in stage_tasks:
    print(t['id'])
"
