# Research: Usage Limits & Scheduling (minordomo-17u)

## Current State

`majordomo/system-prompt.md` Step 2 is a stub that logs `status: skipped` unconditionally.
`shared/config.yaml` already has `schedule` and `usage` blocks (marked "Stage 5 — not yet enforced").

## Claude Usage API

- Endpoint: `https://api.anthropic.com/api/oauth/usage`
- Auth: `Authorization: Bearer <CLAUDE_CODE_OAUTH_TOKEN>` + `anthropic-beta: oauth-2025-04-20`
- Token available in Jenkins as env var `CLAUDE_CODE_OAUTH_TOKEN` (already in `majordomo/Jenkinsfile`)
- Response shape (from reference `claude_quota.py`):
  ```json
  {
    "five_hour": {"utilization": 45.2, "resets_at": "..."},
    "seven_day":  {"utilization": 32.1, "resets_at": "..."}
  }
  ```
- Weekly usage = `seven_day.utilization` (float, 0–100)
- Compare against `usage.weekly_threshold_pct` from config (default: 50)
- Unofficial/undocumented endpoint → fail-open: if unavailable or unexpected shape, log and proceed

## Schedule Config

```yaml
schedule:
  allowed_days: [Mon, Tue, Wed, Thu, Fri]
  allowed_hours: ["00:00-08:00", "18:00-23:59"]
  weekend_override: false
```

- `allowed_days`: day-of-week names (Mon, Tue, Wed, Thu, Fri, Sat, Sun)
- `allowed_hours`: list of `"HH:MM-HH:MM"` ranges; inside any range = allowed
- Timezone: **unspecified** — needs clarification (UTC vs. local)
- If outside window → exit 0 with log (no agents launched)

## New Scripts Needed

- `shared/check-schedule.py` — reads config, checks wall clock, exit 0 if in window / exit 1 if outside
- `shared/check-usage.py` — calls OAuth usage API, exit 0 if under threshold / exit 1 if at/above
- Tests: `test/bats/check-schedule.bats`, `test/bats/check-usage.bats`

## Jenkinsfile Cron

- Add `triggers { cron('...') }` to `majordomo/Jenkinsfile`
- Since schedule gating is in code, Jenkins cron can be broad (e.g., every 30 min weekdays)
- Code gates at runtime; Jenkinsfile just ensures the job fires frequently enough

## Run Log Step Naming

Split Step 2 into two named steps in the run log:
- `"schedule_check"` — time-of-day gating result
- `"usage_check"` — Claude API usage result

Each emits `status: ok` (and `action: proceed` or `action: exit`) so the log shows what happened.

## Resolved Questions

**Timezone for schedule comparison** — issue author confirmed: use **ET (America/New_York)**. Add `timezone: America/New_York` to the `schedule` block in `shared/config.yaml`. Use Python `zoneinfo` (available in Python 3.13 in the agent container; no pytz needed).
