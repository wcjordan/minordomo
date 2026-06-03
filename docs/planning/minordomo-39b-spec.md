# Implementation Plan: Fix check-usage.py 403 (minordomo-39b)

Switch `check-usage.py` from the broken `api.anthropic.com/api/oauth/usage`
endpoint to `https://claude.ai/api/organizations/<org-id>/usage`, injecting
the org ID from a new `claude-org-id` Jenkins credential.

---

## Stage 1: Update check-usage.py and tests for claude.ai organization endpoint

### Description

Rewrite `shared/check-usage.py` to construct the API URL from a `CLAUDE_ORG_ID`
environment variable instead of using the hard-coded Anthropic endpoint.

Changes:
- Remove `DEFAULT_API_URL = "https://api.anthropic.com/api/oauth/usage"`.
- Add URL construction: if `CLAUDE_USAGE_API_URL` is set, use it (existing test
  override); otherwise construct `https://claude.ai/api/organizations/{org_id}/usage`
  from `CLAUDE_ORG_ID`. If neither is available, call `fail_open` with a warning.
- Remove the `anthropic-beta: oauth-2025-04-20` request header; keep
  `Authorization: Bearer {token}`.
- Response parsing (`data["seven_day"]["utilization"]`) is unchanged.
- Update `test/bats/check-usage.bats`:
  - Add test: `CLAUDE_ORG_ID` not set (and no URL override) → exits 0, action=proceed, warning present.
  - Update existing fixture responses to include the full new shape
    (`five_hour`, `seven_day`, extra fields) to confirm parsing is robust.
  - All existing tests remain green (they use `CLAUDE_USAGE_API_URL` override,
    so `CLAUDE_ORG_ID` is not required).

### Acceptance Criteria
- `make test` passes with all existing and new bats tests green.
- `check-usage.py` exits 0 (fail-open) when `CLAUDE_ORG_ID` is unset and
  `CLAUDE_USAGE_API_URL` is also unset.
- `check-usage.py` exits 0 (fail-open) when `CLAUDE_CODE_OAUTH_TOKEN` is unset.
- `check-usage.py` correctly exits 0 or 1 based on `seven_day.utilization`
  when the mock server returns the new response shape.
- No `anthropic-beta` header is sent in requests.

---

## Stage 2: Update Jenkinsfile to inject claude-org-id credential

### Description

Add `CLAUDE_ORG_ID` to the `majordomo/Jenkinsfile` environment block so
`check-usage.py` receives the org ID at runtime.

Changes:
- In `majordomo/Jenkinsfile`, add to the `environment` block:
  ```
  // Prereq: create a Jenkins "Secret text" credential named 'claude-org-id'.
  CLAUDE_ORG_ID = credentials('claude-org-id')
  ```
  Place it adjacent to the existing `DISCORD_WEBHOOK_URL` line.
- No changes to `shared/agent-pipeline.Jenkinsfile` (that pipeline does not
  call `check-usage.py`).

### Acceptance Criteria
- `majordomo/Jenkinsfile` contains `CLAUDE_ORG_ID = credentials('claude-org-id')`.
- A comment documents the prerequisite credential.
- `make test` (shellcheck, bats) still passes.
- No other files are modified in this stage.
