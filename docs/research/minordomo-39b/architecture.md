# check-usage.py: Current State and Fix Context

## Problem

`shared/check-usage.py` calls `https://api.anthropic.com/api/oauth/usage` with a
Bearer `CLAUDE_CODE_OAUTH_TOKEN` and `anthropic-beta: oauth-2025-04-20` header.
This endpoint returns 403. A previous fix attempt (fd8d3e8, reverted in 625c2cc)
tried four different auth header combinations in sequence — all returned 403.

## Owner Decision

Switch to `https://claude.ai/api/organizations/<org-id>/usage`.
A new Jenkins "Secret text" credential called `claude-org-id` will provide the org ID.

## New Endpoint Response Shape

```json
{
  "five_hour": { "utilization": 20, "resets_at": "..." },
  "seven_day":  { "utilization": 32, "resets_at": "..." },
  ...
}
```

`seven_day.utilization` is the same field already parsed — no change needed there.

## Key Files

- `shared/check-usage.py` — usage check script
- `test/bats/check-usage.bats` — bats tests (use `CLAUDE_USAGE_API_URL` to point at mock server)
- `majordomo/Jenkinsfile` — runs `check-usage.py`; currently injects `CLAUDE_CODE_OAUTH_TOKEN`
- `shared/config.yaml` — `usage.weekly_threshold_pct: 85`

## URL Construction Logic

- `CLAUDE_USAGE_API_URL` env var → use directly (existing override for tests)
- Otherwise, construct from `CLAUDE_ORG_ID` env var:
  `https://claude.ai/api/organizations/{CLAUDE_ORG_ID}/usage`
- If neither is set, fail-open (same behaviour as missing token)

## Auth Headers

Remove `anthropic-beta: oauth-2025-04-20`. Keep `Authorization: Bearer {token}`.
The claude.ai API uses the same OAuth token.

## Jenkinsfile

Only `majordomo/Jenkinsfile` calls `check-usage.py`.
Add `CLAUDE_ORG_ID = credentials('claude-org-id')` to the `environment` block,
following the same pattern as `DISCORD_WEBHOOK_URL`.
