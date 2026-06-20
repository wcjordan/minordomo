# Research: Claude Usage Check Architecture

## Current Implementation

`shared/check-usage.py` checks weekly Claude API utilization before launching agents.

### How It Works

1. Reads `CLAUDE_CODE_OAUTH_TOKEN` from environment
2. Reads `CLAUDE_ORG_ID` from environment (or uses `CLAUDE_USAGE_API_URL` override for tests)
3. Constructs URL: `https://claude.ai/api/organizations/{org_id}/usage`
4. Makes HTTP GET request with Bearer token auth
5. Parses `data["seven_day"]["utilization"]` from JSON response
6. Compares against `usage.weekly_threshold_pct` from `shared/config.yaml` (default 50)
7. Exits 0 (proceed) or 1 (skip) — fail-open on any error

### How It's Invoked (majordomo/Jenkinsfile)

```sh
USAGE_EXIT=0
USAGE_JSON=$(python3 shared/check-usage.py) || USAGE_EXIT=$?
echo "$USAGE_JSON" > /tmp/usage-check.json
echo "$USAGE_EXIT" > /tmp/usage-check.exit
```

Then Claude reads `/tmp/usage-check.json` and `/tmp/usage-check.exit` after invocation.

### Credentials Required
- `CLAUDE_CODE_OAUTH_TOKEN` — the main Claude auth token
- `CLAUDE_ORG_ID` — a separate Jenkins credential (`claude-org-id`) needed for the API endpoint

## The Problem

The `https://claude.ai/api/organizations/{org_id}/usage` endpoint doesn't work. Either
the endpoint moved, the auth mechanism changed, or the org_id credential is stale/incorrect.

## FUTURE_WORK.md Reference

docs/FUTURE_WORK.md mentions `https://api.anthropic.com/api/oauth/usage` as the
reference endpoint (from https://github.com/slopware/claude-quota). This is a DIFFERENT
endpoint from what check-usage.py uses — it's OAuth-based and doesn't require org_id.

## Proposed Fix: Claude CLI /usage Command

The issue suggests running `claude` interactively and sending the `/usage` slash command.
In Claude Code interactive mode, `/usage` displays usage information for the account.

### Key Questions for Worker to Investigate

1. What does `claude /usage` output when run interactively? Does it show weekly utilization
   % or just per-session token counts?
2. How to capture output: TTY via script(1) (as in run-claude.sh) or some other mechanism?

### If /usage Shows Weekly Utilization
Implement a wrapper script that:
1. Runs `claude` with a TTY
2. Sends `/usage` as input
3. Captures and parses the output text
4. Applies threshold logic from config.yaml

### If /usage Only Shows Session Tokens
Fall back to the `https://api.anthropic.com/api/oauth/usage` endpoint (OAuth-based,
no org_id needed — just the OAuth token) as mentioned in FUTURE_WORK.md.

## Interactive Mode Context

`shared/run-claude.sh` runs claude interactively using:
```bash
script -q -e -c 'PROMPT=$(cat /tmp/system-prompt.md); exec claude --dangerously-skip-permissions "$PROMPT"' /dev/null
```

This pattern could be adapted to run claude, send `/usage`, and capture the text output.

## Files to Modify

- `shared/check-usage.py` — core change (replace HTTP API with claude CLI approach)
- `shared/config.yaml` — no change needed (threshold still applies)
- `majordomo/Jenkinsfile` — remove `CLAUDE_ORG_ID` credential if no longer needed
- `test/bats/check-usage.bats` — update tests to match new implementation
