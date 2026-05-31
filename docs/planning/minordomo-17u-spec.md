# Implementation Plan: Usage Limits & Scheduling

**Epic:** minordomo-17u  
**GH Issue:** https://github.com/wcjordan/minordomo/issues/208

---

## Stage 1: Schedule check script and config

### Description

Create `shared/check-schedule.py` to gate on the configured time-of-day schedule, add
`timezone: America/New_York` to the `schedule` block in `shared/config.yaml`, and write
bats tests for the script.

The script:
- Reads `shared/config.yaml` (located relative to `__file__`).
- Gets the current datetime in `schedule.timezone` (default: `America/New_York`) using `zoneinfo`.
- Checks whether the current day (3-letter abbreviation, e.g. `Mon`) is in `allowed_days`.
- Checks whether the current time falls within any `HH:MM-HH:MM` range in `allowed_hours`.
- Special rule — `weekend_override`: if set to `true`, always exit 0 on Saturday or Sunday
  regardless of `allowed_days` or `allowed_hours`.
- Exits 0 if in-window (proceed), exits 1 if outside the window (skip).
- Writes a JSON object to stdout on both paths:
  - In-window: `{"step": "schedule_check", "status": "ok", "action": "proceed"}`
  - Outside window: `{"step": "schedule_check", "status": "ok", "action": "exit", "reason": "<day_not_allowed|outside_hours>"}`

Config change — add `timezone` to `shared/config.yaml` under `schedule`:

```yaml
schedule:
  allowed_days: [Mon, Tue, Wed, Thu, Fri]
  allowed_hours: ["00:00-08:00", "18:00-23:59"]
  weekend_override: false
  timezone: America/New_York
```

Bats test file `test/bats/check-schedule.bats`:
- Mock wall-clock time by passing `--now "YYYY-MM-DDTHH:MM:SS"` as the first argument to
  the script (script uses this value instead of `datetime.now()` when provided).
- Tests:
  1. Weekday in allowed hours → exits 0
  2. Weekday outside allowed hours → exits 1 with `reason: outside_hours`
  3. Day not in `allowed_days` (Saturday when override=false) → exits 1 with `reason: day_not_allowed`
  4. Saturday with `weekend_override: true` → exits 0 even though Sat not in allowed_days
  5. Midnight boundary — time exactly at range start/end edge → exits 0 (ranges are inclusive)

### Acceptance Criteria

- `shared/check-schedule.py` exists and exits 0 when current time is within `allowed_days` + `allowed_hours` in configured timezone; exits 1 otherwise
- `weekend_override: true` causes the script to exit 0 on Saturday/Sunday regardless of `allowed_days`/`allowed_hours`
- Script accepts `--now "ISO-datetime-string"` argument to override wall-clock time (for testing)
- `shared/config.yaml` has `timezone: America/New_York` in the `schedule` block
- All bats tests in `test/bats/check-schedule.bats` pass
- `make test` passes

---

## Stage 2: Usage check script and tests

### Description

Create `shared/check-usage.py` to gate on the weekly Claude API usage limit, and write
bats tests for the script.

The script:
- Reads `usage.weekly_threshold_pct` from `shared/config.yaml` (default: 50).
- Reads `CLAUDE_CODE_OAUTH_TOKEN` from the environment.
- Makes a GET request to the usage endpoint (default: `https://api.anthropic.com/api/oauth/usage`;
  overridable via `CLAUDE_USAGE_API_URL` env var for testing).
  - Headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`
- Extracts `seven_day.utilization` from the response JSON.
- If `utilization >= threshold`: writes JSON to stdout and exits 1 (skip):
  `{"step": "usage_check", "status": "ok", "action": "exit", "reason": "usage_over_threshold", "utilization": <float>, "threshold": <int>}`
- If `utilization < threshold`: writes JSON to stdout and exits 0 (proceed):
  `{"step": "usage_check", "status": "ok", "action": "proceed", "utilization": <float>, "threshold": <int>}`
- **Fail-open** on all error conditions — exits 0 with a warning in the JSON:
  - `CLAUDE_CODE_OAUTH_TOKEN` not set
  - HTTP error (non-200 status, network failure, timeout)
  - Response body is not valid JSON or missing `seven_day.utilization`
  - In all fail-open cases: `{"step": "usage_check", "status": "ok", "action": "proceed", "warning": "<reason>"}`
- Use `urllib.request` (stdlib only, no third-party HTTP library required).

Bats test file `test/bats/check-usage.bats` using a fixed-port Python mock HTTP server:
- `setup()` writes fixture JSON to `$TMP_DIR/response.json`, starts a Python mock server on
  port 18999 in the background, and sets `CLAUDE_USAGE_API_URL=http://127.0.0.1:18999/usage`.
- `teardown()` kills the mock server and removes `$TMP_DIR`.
- Tests:
  1. Utilization below threshold (30%) → exits 0
  2. Utilization at threshold (50%) → exits 1
  3. Utilization above threshold (75%) → exits 1
  4. `CLAUDE_CODE_OAUTH_TOKEN` not set → exits 0 (fail-open with warning)
  5. Server returns non-200 status → exits 0 (fail-open with warning)
  6. Server returns malformed JSON → exits 0 (fail-open with warning)
  7. Response missing `seven_day.utilization` field → exits 0 (fail-open with warning)

The mock server in bats setup:

```bash
python3 - <<'PYEOF' &
import http.server, os, json, time

RESPONSE_FILE = os.environ['TMP_DIR'] + '/response.json'

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = open(RESPONSE_FILE, 'rb').read()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass

http.server.HTTPServer(('127.0.0.1', 18999), Handler).serve_forever()
PYEOF
MOCK_PID=$!
sleep 0.3  # let server bind
export MOCK_PID
```

### Acceptance Criteria

- `shared/check-usage.py` exits 1 when `seven_day.utilization >= weekly_threshold_pct`; exits 0 otherwise
- Script is fail-open: exits 0 if token missing, API unavailable, or response shape unexpected
- `CLAUDE_USAGE_API_URL` env var overrides the default endpoint URL
- All bats tests in `test/bats/check-usage.bats` pass
- `make test` passes

---

## Stage 3: Wire Step 2, add Jenkinsfile cron, update run log example

### Description

Replace the Step 2 stub in `majordomo/system-prompt.md` with real instructions that call
both check scripts, add a cron trigger to `majordomo/Jenkinsfile`, and update the run log
example at the bottom of `system-prompt.md` to reflect the new step shape.

**`majordomo/system-prompt.md` — Step 2 rewrite:**

Remove the entire ⚠️ stub block. Replace it with:

```
### Step 2: Check Schedule and Usage Limits

Run schedule and usage checks. Capture each script's stdout (JSON) and exit code.

1. Run `python3 shared/check-schedule.py`. Capture the JSON output and exit code.
   - If exit code is 1: include the captured JSON as the `schedule_check` step in the run log,
     emit the run log (status: "success"), and exit 0 — outside the schedule window is expected, not an error.
   - If exit code is 0: record the captured JSON as the `schedule_check` step and continue.

2. Run `python3 shared/check-usage.py`. Set `CLAUDE_CODE_OAUTH_TOKEN` from the environment.
   Capture the JSON output and exit code.
   - If exit code is 1: include the captured JSON as the `usage_check` step in the run log,
     emit the run log (status: "success"), and exit 0 — over-quota is expected, not an error.
   - If exit code is 0: record the captured JSON as the `usage_check` step and continue.
```

**`majordomo/Jenkinsfile` — add cron trigger:**

Add a `triggers { ... }` block at pipeline level, after the `options { ... }` block:

```groovy
triggers {
    cron('H/30 * * * 1-5')
}
```

This fires approximately every 30 minutes on weekdays. The code gates schedule and usage at
runtime; the Jenkins cron is intentionally broad so the pipeline checks frequently enough.

**`system-prompt.md` run log example — update the `schedule_check` entry:**

Replace the current stub entry:
```json
{"step": "schedule_check", "status": "skipped", "message": "not yet implemented — always proceeding"},
```

With two entries reflecting the new shape:
```json
{"step": "schedule_check", "status": "ok", "action": "proceed"},
{"step": "usage_check", "status": "ok", "action": "proceed"},
```

### Acceptance Criteria

- Step 2 in `majordomo/system-prompt.md` calls both scripts, exits 0 with a valid run log if either
  returns exit code 1, and continues the pipeline if both return exit code 0
- The ⚠️ "NOT YET IMPLEMENTED" stub is removed
- The run log example in `system-prompt.md` shows `schedule_check` and `usage_check` with
  `action: proceed` instead of the stub `status: skipped` entry
- `majordomo/Jenkinsfile` has `triggers { cron('H/30 * * * 1-5') }` at pipeline level, after the `options` block
- `make test` passes
