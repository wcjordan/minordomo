# Research: check-usage.py 403 Issue (minordomo-92i)

## Problem Summary

`shared/check-usage.py` calls `https://api.anthropic.com/api/oauth/usage` with:
- `Authorization: Bearer <CLAUDE_CODE_OAUTH_TOKEN>`
- `anthropic-beta: oauth-2025-04-20`

It receives a 403 response and calls `fail_open()`, which exits 0 with a warning. The usage gate is therefore never enforced — Majordomo always proceeds regardless of usage level.

## Codebase Context

### check-usage.py
- `shared/check-usage.py` — the script that checks usage
- Uses `CLAUDE_CODE_OAUTH_TOKEN` env var for auth
- Supports `CLAUDE_USAGE_API_URL` env var override for testing
- On HTTPError (including 403), calls `fail_open(f"HTTP error: {e.code}")` — does NOT log the response body
- Tests in `test/bats/check-usage.bats`

### Jenkinsfile Integration
- `majordomo/Jenkinsfile` captures usage check output/exit code into `/tmp/usage-check.json` and `/tmp/usage-check.exit`
- Unlike schedule check (which exits the shell script early if non-zero), the usage check result is passed to Claude via files
- Majordomo's system prompt reads those files and decides whether to proceed
- So the gate is implemented inside Claude's reasoning, not in shell logic

### The Original Implementation
- Added in PR #270: "Add schedule and usage-limit gating to Majordomo"
- Reference implementation cited: `claude_quota.py` (third-party GitHub project)
- The PR description notes: "This endpoint is unofficial and undocumented; verify it works before relying on it"

## Root Cause Theories

The script doesn't log the HTTP response body, so we don't know exactly why it's 403. Possible theories:

1. **Wrong/outdated beta header** — `anthropic-beta: oauth-2025-04-20` may be outdated or deprecated
2. **Missing required header** — endpoint might require `anthropic-version: 2023-06-01` 
3. **Token scope mismatch** — OAuth token may lack the scope to access usage data
4. **Endpoint URL changed** — `https://api.anthropic.com/api/oauth/usage` may have moved
5. **Token type mismatch** — The Jenkins credential might be an API key disguised as an OAuth token

## Diagnostic Gap

The critical missing info: the 403 response body likely contains an error message explaining exactly why auth failed. Currently `urllib.error.HTTPError.read()` is never called — only `.code` is logged.

## Fix Approach

**Stage 1:** Log the full HTTP response body on errors, and create a diagnostic probe script that tries multiple auth approaches (different headers, endpoint variants) to identify which one works in the live environment.

**Stage 2:** Update `check-usage.py` to use the confirmed working auth approach, with comprehensive tests.

## Related Files
- `shared/check-usage.py` — main script
- `test/bats/check-usage.bats` — tests  
- `shared/config.yaml` — usage threshold config (currently 85%)
- `majordomo/Jenkinsfile` — how results are captured and passed to Majordomo
- `majordomo/system-prompt.md` — how Majordomo interprets usage check results
