#!/usr/bin/env python3
"""Check Claude API weekly usage against configured threshold.

Exits 0 (proceed) when utilization < threshold or on any error (fail-open).
Exits 1 (skip) when utilization >= threshold.

Reads usage.weekly_threshold_pct from shared/config.yaml (default: 50).
Reads CLAUDE_CODE_OAUTH_TOKEN from the environment.
CLAUDE_USAGE_API_URL env var overrides the default endpoint.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

import yaml

CONFIG_PATH = Path(__file__).parent / "config.yaml"
DEFAULT_API_URL = "https://api.anthropic.com/api/oauth/usage"


def load_threshold():
    try:
        with open(CONFIG_PATH) as f:
            config = yaml.safe_load(f)
        return int(config.get("usage", {}).get("weekly_threshold_pct", 50))
    except Exception:
        return 50


def fail_open(warning):
    print(json.dumps({"step": "usage_check", "status": "ok", "action": "proceed", "warning": warning}))
    sys.exit(0)


def main():
    threshold = load_threshold()
    token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "")
    api_url = os.environ.get("CLAUDE_USAGE_API_URL", DEFAULT_API_URL)

    if not token:
        fail_open("CLAUDE_CODE_OAUTH_TOKEN not set")

    req = urllib.request.Request(
        api_url,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        fail_open(f"HTTP error: {e.code}")
    except Exception as e:
        fail_open(f"request failed: {e}")

    try:
        data = json.loads(body)
        utilization = data["seven_day"]["utilization"]
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        fail_open(f"unexpected response shape: {e}")

    if utilization >= threshold:
        print(json.dumps({
            "step": "usage_check",
            "status": "ok",
            "action": "exit",
            "reason": "usage_over_threshold",
            "utilization": utilization,
            "threshold": threshold,
        }))
        sys.exit(1)
    else:
        print(json.dumps({
            "step": "usage_check",
            "status": "ok",
            "action": "proceed",
            "utilization": utilization,
            "threshold": threshold,
        }))
        sys.exit(0)


if __name__ == "__main__":
    main()
