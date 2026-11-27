#!/usr/bin/env bash
# Output a JSON array of ready implementation tasks.
# Excludes Plan: and Story: tasks, and any task whose parent is not a Story: bead
# (including tasks with no parent, e.g. hand-filed beads). Such tasks cannot be
# resolved by get-story-key.sh, so they are skipped with a note on stderr.
# Usage: shared/list-impl-tasks-ready.sh

set -euo pipefail

bd ready --json | python3 -c "
import json, subprocess, sys

tasks = json.load(sys.stdin)
parent_is_story = {}

def is_story(parent_id):
    if parent_id not in parent_is_story:
        try:
            out = subprocess.run(['bd', 'show', parent_id, '--json'],
                                 capture_output=True, text=True, check=True).stdout
            data = json.loads(out) if out.strip() else []
            title = (data[0].get('title') or '') if data else ''
        except (subprocess.CalledProcessError, ValueError, IndexError, AttributeError):
            title = ''
        parent_is_story[parent_id] = title.startswith('Story:')
    return parent_is_story[parent_id]

impl = []
for t in tasks:
    if t.get('title', '').startswith(('Plan:', 'Story:')):
        continue
    parent = t.get('parent')
    if not parent:
        print(f\"list-impl-tasks-ready: skipping {t.get('id')}: no parent Story bead\", file=sys.stderr)
        continue
    if not is_story(parent):
        print(f\"list-impl-tasks-ready: skipping {t.get('id')}: parent {parent} is not a Story bead\", file=sys.stderr)
        continue
    impl.append(t)
print(json.dumps(impl))
"
