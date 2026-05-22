#!/usr/bin/env python3
"""Read claude --output-format json output and print a token usage summary."""

import json
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: report-token-usage.py <claude-output.json>")
        return

    path = sys.argv[1]
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


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Warning: unexpected error: {e}")
