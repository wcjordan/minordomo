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

With --transcript <path>: reads the Claude Code JSONL transcript instead, collects
all assistant text entries, and runs the same has_errors() check on the combined text.

Exits 1 if errors are detected, 0 otherwise. Exits 0 on any read/parse error
so a missing or malformed log never falsely fails a build.
"""

import argparse
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


def read_transcript_text(path):
    """Collect all assistant text content from a Claude Code JSONL transcript."""
    parts = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if entry.get('type') != 'assistant':
                    continue
                msg = entry.get('message', {})
                content = msg.get('content', [])
                if isinstance(content, list):
                    text = ''.join(
                        c.get('text', '') for c in content
                        if isinstance(c, dict) and c.get('type') == 'text'
                    )
                    if text:
                        parts.append(text)
                elif isinstance(content, str) and content:
                    parts.append(content)
    except Exception:
        return ''
    return '\n'.join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file', nargs='?', help='path to run log file')
    parser.add_argument('--transcript', metavar='PATH', help='Claude Code JSONL transcript file')
    args = parser.parse_args()

    if args.transcript:
        content = read_transcript_text(args.transcript)
        sys.exit(1 if has_errors(content) else 0)

    if not args.file:
        print("Usage: check-run-errors.py <path-to-run-log>", file=sys.stderr)
        sys.exit(0)

    try:
        content = open(args.file).read()
        sys.exit(1 if has_errors(content) else 0)
    except Exception:
        sys.exit(0)


if __name__ == "__main__":
    main()
