#!/usr/bin/env python3
"""Read claude --output-format json output and print a token usage summary."""

import json
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: report-token-usage.py <claude-output.json>", file=sys.stderr)
        sys.exit(0)

    path = sys.argv[1]
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Warning: {path} not found; skipping token usage report.")
        sys.exit(0)
    except Exception as e:
        print(f"Warning: could not parse {path}: {e}; skipping token usage report.")
        sys.exit(0)

    result = data.get("result", "")
    print("=== Agent Output ===")
    print(result)
    print()

    usage = data.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    cache_read = usage.get("cache_read_input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    cost = data.get("total_cost_usd", 0.0)
    duration_ms = data.get("duration_ms", 0)
    duration_s = duration_ms / 1000.0

    print("=== Token Usage ===")
    print(f"  Input tokens:      {input_tokens:,}")
    print(f"  Cache read tokens: {cache_read:,}")
    print(f"  Output tokens:     {output_tokens:,}")
    print(f"  Cost (USD):        ${cost:.4f}")
    print(f"  Duration:          {duration_s:.1f}s")


if __name__ == "__main__":
    main()
