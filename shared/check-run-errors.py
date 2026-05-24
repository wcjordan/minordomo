#!/usr/bin/env python3
"""Scan an agent run-log for error signals.

Reads the file at argv[1] (typically /tmp/prompt-output.txt) and scans for the
last JSON line in the file. If that line has status=='failure' or a non-empty
'errors' field, exits 1; otherwise exits 0. Exits 0 on any read/parse error so
a missing or malformed log never falsely fails a build.

Contract: the last JSON line in the file is authoritative — earlier JSON lines
are ignored. If report-token-usage.py ever appends JSON after the agent output,
update this assumption accordingly.
"""

import json
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: check-run-errors.py <path-to-run-log>", file=sys.stderr)
        sys.exit(0)

    try:
        lines = open(sys.argv[1]).read().splitlines()
        for line in reversed(lines):
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
                sys.exit(1 if d.get('status') == 'failure' or d.get('errors') else 0)
            except (json.JSONDecodeError, ValueError):
                continue
        sys.exit(0)
    except Exception:
        sys.exit(0)


if __name__ == "__main__":
    main()
