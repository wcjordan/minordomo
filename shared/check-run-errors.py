#!/usr/bin/env python3
"""Scan an agent run-log for error signals.

Reads the file at argv[1] (typically /tmp/prompt-output.txt) and checks for
errors using two strategies:

1. JSON code blocks: parse any ```json ... ``` block in the file as a run-log
   document and check for a non-empty 'errors' array or status=='failure'.
   This handles the real agent output format where the run log is emitted as
   a markdown-fenced JSON block.

2. Last JSON line (fallback): scan lines in reverse for the last parseable JSON
   object. Handles compact single-line JSON output (e.g. the test-fixture format
   where the claude result field is a single-line JSON string).

Exits 1 if errors are detected, 0 otherwise. Exits 0 on any read/parse error
so a missing or malformed log never falsely fails a build.
"""

import json
import re
import sys


def has_errors(content):
    # Primary: parse JSON from markdown code blocks
    for match in re.finditer(r'```(?:json)?\s*\n(.*?)```', content, re.DOTALL):
        try:
            d = json.loads(match.group(1))
            if d.get('status') == 'failure' or d.get('errors'):
                return True
        except (json.JSONDecodeError, ValueError):
            continue

    # Fallback: last parseable JSON line (compact single-line result format)
    for line in reversed(content.splitlines()):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
            return d.get('status') == 'failure' or bool(d.get('errors'))
        except (json.JSONDecodeError, ValueError):
            continue

    return False


def main():
    if len(sys.argv) < 2:
        print("Usage: check-run-errors.py <path-to-run-log>", file=sys.stderr)
        sys.exit(0)

    try:
        content = open(sys.argv[1]).read()
        sys.exit(1 if has_errors(content) else 0)
    except Exception:
        sys.exit(0)


if __name__ == "__main__":
    main()
