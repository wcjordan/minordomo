#!/usr/bin/env python3
"""Read claude --output-format json output and print a token usage summary."""

import argparse
import json
import sys


def report_transcript(path):
    """Parse a Claude Code JSONL transcript and print token usage summary."""
    input_tokens = 0
    output_tokens = 0
    cache_read = 0
    last_text = ''

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
                usage = msg.get('usage', {}) or {}
                input_tokens += usage.get('input_tokens', 0) or 0
                output_tokens += usage.get('output_tokens', 0) or 0
                cache_read += usage.get('cache_read_input_tokens', 0) or 0
                content = msg.get('content', [])
                if isinstance(content, list):
                    text = ''.join(
                        c.get('text', '') for c in content
                        if isinstance(c, dict) and c.get('type') == 'text'
                    )
                    last_text = text
                elif isinstance(content, str):
                    last_text = content
    except FileNotFoundError:
        print(f"Warning: {path} not found; skipping token usage report.")
        return
    except Exception as e:
        print(f"Warning: could not read {path}: {e}; skipping token usage report.")
        return

    print("=== Agent Output ===")
    print(last_text)
    print()
    print("=== Token Usage ===")
    print(f"  Input tokens:      {input_tokens:,}")
    print(f"  Cache read tokens: {cache_read:,}")
    print(f"  Output tokens:     {output_tokens:,}")
    # Cost and duration are not available in JSONL transcripts; omit rather than print zeros


def report_json(path):
    """Parse a claude -p --output-format json file and print token usage summary."""
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Warning: {path} not found; skipping token usage report.")
        return
    except Exception as e:
        print(f"Warning: could not parse {path}: {e}; skipping token usage report.")
        return

    result = data.get("result", "")
    print("=== Agent Output ===")
    print(result)
    print()

    usage = data.get("usage", {}) or {}
    input_tokens = usage.get("input_tokens", 0) or 0
    cache_read = usage.get("cache_read_input_tokens", 0) or 0
    output_tokens = usage.get("output_tokens", 0) or 0
    cost = data.get("total_cost_usd", 0) or 0
    duration_ms = data.get("duration_ms", 0) or 0
    duration_s = duration_ms / 1000.0

    print("=== Token Usage ===")
    print(f"  Input tokens:      {input_tokens:,}")
    print(f"  Cache read tokens: {cache_read:,}")
    print(f"  Output tokens:     {output_tokens:,}")
    print(f"  Cost (USD):        ${cost:.4f}")
    print(f"  Duration:          {duration_s:.1f}s")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file', nargs='?', help='claude --output-format json output file')
    parser.add_argument('--transcript', metavar='PATH', help='Claude Code JSONL transcript file')
    args = parser.parse_args()

    if args.transcript:
        report_transcript(args.transcript)
        return

    if not args.file:
        print("Usage: report-token-usage.py <claude-output.json>")
        return

    report_json(args.file)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Warning: unexpected error: {e}")
