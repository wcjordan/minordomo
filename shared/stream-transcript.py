#!/usr/bin/env python3
"""Stream a Claude JSONL transcript to stdout in human-readable form.

Usage: stream-transcript.py <project-dir>

Watches <project-dir>'s Claude transcript directory for a new session file,
then follows it and prints assistant text, tool calls, and tool results as
they arrive. Designed to run in parallel with run-claude.sh; suppress
run-claude.sh output and let this script provide the visible log.
"""

import json
import os
import re
import sys
import time

POLL_INTERVAL = 0.3  # seconds between readline attempts
FIND_TIMEOUT  = 60   # seconds to wait for transcript file to appear


def transcript_dir(project_dir: str) -> str:
    # Claude Code escapes the project path by replacing every non-alphanumeric,
    # non-hyphen character (including leading /, _, etc.) with a hyphen.
    escaped = re.sub(r'[^a-zA-Z0-9-]', '-', project_dir)
    return os.path.expanduser(f'~/.claude/projects/{escaped}')


def find_transcript(project_dir: str) -> str | None:
    """Return path to the new JSONL file that appears after we start watching."""
    tdir = transcript_dir(project_dir)
    existing: set[str] = set()
    if os.path.isdir(tdir):
        existing = {f for f in os.listdir(tdir) if f.endswith('.jsonl')}

    deadline = time.time() + FIND_TIMEOUT
    while time.time() < deadline:
        if os.path.isdir(tdir):
            current = {f for f in os.listdir(tdir) if f.endswith('.jsonl')}
            new = current - existing
            if new:
                return os.path.join(tdir, max(new, key=lambda f: os.path.getmtime(os.path.join(tdir, f))))
        time.sleep(POLL_INTERVAL)
    return None


def fmt_tool_input(name: str, inp: dict) -> str:
    if name == 'Bash':
        desc = inp.get('description', '')
        cmd  = inp.get('command', '')
        return f"$ {cmd}" + (f"  # {desc}" if desc else '')
    path = inp.get('file_path') or inp.get('path') or ''
    if path:
        return path
    pairs = [f"{k}={repr(v)[:60]}" for k, v in list(inp.items())[:2]]
    return ', '.join(pairs)


def fmt_tool_result(content) -> str:
    """Extract text from a tool_result content block, truncated."""
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        parts = [b.get('text', '') for b in content if isinstance(b, dict) and b.get('type') == 'text']
        text = '\n'.join(parts)
    else:
        return ''
    text = text.strip()
    lines = text.splitlines()
    limit = 20
    if len(lines) > limit:
        shown = lines[:limit]
        shown.append(f'... ({len(lines) - limit} more lines)')
        return '\n'.join(shown)
    return text


def stream(path: str) -> None:
    # printed[msg_id] = set of content-block indices already printed
    printed: dict[str, set[int]] = {}

    with open(path, 'r') as fh:
        while True:
            line = fh.readline()
            if not line:
                time.sleep(POLL_INTERVAL)
                continue
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            etype = entry.get('type')

            if etype == 'assistant':
                msg    = entry.get('message', {})
                msg_id = msg.get('id', '')
                blocks = msg.get('content', [])
                done   = printed.setdefault(msg_id, set())
                for i, block in enumerate(blocks):
                    if i in done:
                        continue
                    btype = block.get('type')
                    if btype == 'text':
                        text = block.get('text', '').strip()
                        if text:
                            print(f'\n[Claude] {text}', flush=True)
                            done.add(i)
                    elif btype == 'tool_use':
                        name = block.get('name', '')
                        inp  = block.get('input', {})
                        print(f'  [{name}] {fmt_tool_input(name, inp)}', flush=True)
                        done.add(i)

            elif etype == 'user':
                # Tool results live inside user messages
                for block in entry.get('message', {}).get('content', []):
                    if not isinstance(block, dict):
                        continue
                    if block.get('type') == 'tool_result':
                        result_text = fmt_tool_result(block.get('content', ''))
                        if result_text:
                            # Indent result under the tool call
                            indented = '\n'.join('    ' + l for l in result_text.splitlines())
                            print(indented, flush=True)


def main() -> None:
    if len(sys.argv) < 2:
        print('Usage: stream-transcript.py <project-dir>', file=sys.stderr)
        sys.exit(1)

    project_dir = sys.argv[1]
    print(f'[transcript] watching {transcript_dir(project_dir)} for new session...', flush=True)

    path = find_transcript(project_dir)
    if not path:
        print('[transcript] timed out waiting for transcript file', file=sys.stderr)
        sys.exit(1)

    print(f'[transcript] streaming {os.path.basename(path)}', flush=True)
    stream(path)


if __name__ == '__main__':
    main()
