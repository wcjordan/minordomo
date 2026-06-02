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

# Auth approaches tried in sequence on 4xx responses.
# Each entry is a dict of headers to include (Authorization added automatically).
AUTH_APPROACHES = [
    # A: current approach
    {"anthropic-beta": "oauth-2025-04-20"},
    # B: bearer only, no beta header
    {},
    # C: bearer + version, no beta header
    {"anthropic-version": "2023-06-01"},
    # D: bearer + version + beta header
    {"anthropic-version": "2023-06-01", "anthropic-beta": "oauth-2025-04-20"},
]


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

    attempts = []

    for approach_index, extra_headers in enumerate(AUTH_APPROACHES):
        headers = {"Authorization": f"Bearer {token}"}
        headers.update(extra_headers)
        req = urllib.request.Request(api_url, headers=headers)

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                body = resp.read()
            # Success — parse and return result
            break
        except urllib.error.HTTPError as e:
            status_code = e.code
            try:
                body_text = e.read().decode("utf-8", errors="replace")
            except Exception:
                body_text = ""

            if 400 <= status_code < 500:
                # Auth error — record and try next approach
                attempts.append({"approach": approach_index, "status": status_code, "body": body_text})
                continue
            else:
                # Non-4xx (e.g. 503) — fail open immediately, no retry
                fail_open(f"HTTP error: {status_code}, body: {body_text}")
        except Exception as e:
            fail_open(f"request failed: {e}")
    else:
        # All approaches failed with 4xx
        diagnostics = "; ".join(
            f"approach {a['approach']}: HTTP {a['status']}, body: {a['body']}"
            for a in attempts
        )
        fail_open(f"all auth approaches failed: {diagnostics}")

    try:
        data = json.loads(body)
        utilization = data["seven_day"]["utilization"]
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        fail_open(f"unexpected response shape: {e}")

    if utilization >= threshold:
        result = {
            "step": "usage_check",
            "status": "ok",
            "action": "exit",
            "reason": "usage_over_threshold",
            "utilization": utilization,
            "threshold": threshold,
        }
        if approach_index > 0:
            result["auth_approach"] = approach_index
        print(json.dumps(result))
        sys.exit(1)
    else:
        result = {
            "step": "usage_check",
            "status": "ok",
            "action": "proceed",
            "utilization": utilization,
            "threshold": threshold,
        }
        if approach_index > 0:
            result["auth_approach"] = approach_index
        print(json.dumps(result))
        sys.exit(0)


if __name__ == "__main__":
    main()
