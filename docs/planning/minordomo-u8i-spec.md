# Implementation Plan: Fetching current Claude usage doesn't work

**GH Issue:** https://github.com/wcjordan/minordomo/issues/396

## Background

`shared/check-usage.py` makes an HTTP request to
`https://claude.ai/api/organizations/{org_id}/usage` to check weekly utilization.
That endpoint no longer works. The fix is to run `claude` interactively via PTY,
send the `/usage` slash command, and parse the weekly utilization percentage from
the output — the same data currently sought from the API is present in `/usage` output.

The `/usage` slash command outputs (confirmed in GH issue #396 comments):
```
Current week (all models)
█                                                  2% used
Resets Jun 21 at 8pm (America/New_York)
```

The implementation spans two stages: a PoC to validate the PTY approach in the real
Jenkins/Kubernetes environment, then a full replacement and cleanup.

---

## Stage 1: PoC — Fetch Claude usage via PTY

### Description

Write `shared/fetch-claude-usage.sh`, a bash script that:

1. Allocates a PTY via `script(1)` (available in the container; util-linux >= 2.37 verified)
2. Runs `claude --dangerously-skip-permissions` interactively in the PTY
3. Sends `/usage` as stdin input after a startup delay, followed by `exit`
4. Captures PTY output to a temp file (not `/dev/null` as in `run-claude.sh`)
5. Strips ANSI escape codes and box-drawing characters from captured output
6. Parses the `N% used` line that follows the `Current week` section
7. Prints the integer percentage (e.g., `2`) to stdout and exits 0 on success
8. Exits non-zero if parsing fails (caller is responsible for fail-open logic)

Wire `fetch-claude-usage.sh` into `majordomo/Jenkinsfile` in **log-only mode** alongside
the existing `check-usage.py` call. The script runs and its raw output is echoed to the
build log, but the result does NOT gate execution — `check-usage.py` still controls
gating in Stage 1. This lets the next Majordomo cron run (every 30 min) produce observable
evidence that the PTY approach works in the real environment.

Write bats unit tests in `test/bats/fetch-claude-usage.bats` that mock `claude` with a
shell script emitting sample `/usage` output, and verify the script correctly extracts
the weekly percentage from it.

**Key implementation notes for the worker:**

- `expect` is NOT available in the container — only `script(1)` and bash are available
  for PTY interaction
- Core challenge is **input timing**: `/usage` must arrive after `claude` finishes starting.
  Candidate approach:
  ```bash
  OUTPUT=$(mktemp)
  (sleep 3; printf '/usage\nexit\n'; sleep 3) | \
    script -q -e -c 'claude --dangerously-skip-permissions' "$OUTPUT" 2>&1 || true
  ```
  Tune the sleep durations based on observed startup latency. If timing is unreliable,
  consider polling the output file for `Current week` and killing the script process
  once the line appears.
- The PTY output contains ANSI escape codes and box-drawing characters; strip before
  parsing (e.g., `sed 's/\x1b\[[0-9;]*m//g'`)
- The script must not hang indefinitely — add a hard timeout (e.g., 30s) and kill the
  claude process if it has not produced parseable output in time

### Acceptance Criteria

- `shared/fetch-claude-usage.sh` exists and is executable
- Script prints an integer percentage (e.g., `15`) to stdout and exits 0 when
  `claude /usage` output is successfully parsed
- Script exits non-zero when output cannot be parsed
- `test/bats/fetch-claude-usage.bats` passes with a mocked `claude` binary that
  emits sample `/usage` output
- `majordomo/Jenkinsfile` includes a log-only invocation of `fetch-claude-usage.sh`
  that echoes its output to the build log without affecting the gating exit code
- After the Stage 1 PR merges, the next Majordomo cron build log shows the raw
  output from `fetch-claude-usage.sh` (confirming PTY works in Jenkins/Kubernetes)
- `make test` passes

---

## Stage 2: Replace check-usage.py and clean up

### Description

Replace the broken HTTP API approach in `shared/check-usage.py` with a call to
`shared/fetch-claude-usage.sh` (from Stage 1). Update the Jenkinsfile to remove the
`CLAUDE_ORG_ID` credential and the log-only wiring from Stage 1.

**`shared/check-usage.py` changes:**

- Replace HTTP request logic with a `subprocess` call to `fetch-claude-usage.sh`
- On subprocess success: use the printed integer as the utilization percentage and apply
  threshold logic (same as current: exit 0 with `action: proceed` when below threshold,
  exit 1 with `action: exit` when at or above)
- On subprocess failure or unparseable output: fail-open (exit 0 with `action: proceed`
  and a `warning` field in the JSON output) — **preserve fail-open semantics exactly**
- Remove `CLAUDE_ORG_ID`/`CLAUDE_USAGE_API_URL` env var handling
- Keep the same JSON output format and exit code contract (Majordomo reads
  `/tmp/usage-check.json` and `/tmp/usage-check.exit`)

**`majordomo/Jenkinsfile` changes:**

- Remove the `CLAUDE_ORG_ID = credentials('claude-org-id')` line and its comment
- Remove the log-only `fetch-claude-usage.sh` invocation added in Stage 1
- The existing `check-usage.py` invocation remains unchanged (it now internally calls
  `fetch-claude-usage.sh`)

**`test/bats/check-usage.bats` changes:**

- Remove the HTTP mock server (Python-based mock server and `CLAUDE_USAGE_API_URL` override)
- Replace with a mock `fetch-claude-usage.sh` that writes a controlled integer to stdout
- Update the `CLAUDE_ORG_ID not set` test case (that env var no longer matters)
- Preserve all existing behavior tests: below threshold exits 0, at/above threshold exits 1,
  failure/missing output exits 0 fail-open with warning

**`docs/FUTURE_WORK.md` changes:**

- Update the "Usage Check" section to describe the new `claude /usage` approach
- Remove the reference to the `https://api.anthropic.com/api/oauth/usage` endpoint
  (no longer the plan)

### Acceptance Criteria

- `shared/check-usage.py` calls `fetch-claude-usage.sh` instead of the HTTP API
- `CLAUDE_ORG_ID` is removed from `majordomo/Jenkinsfile` environment block and from
  `check-usage.py` env var handling
- All `test/bats/check-usage.bats` tests pass with mocked `fetch-claude-usage.sh`
- Fail-open semantics are preserved: any error from `fetch-claude-usage.sh` causes
  `check-usage.py` to exit 0 with `action: proceed` and a `warning` field
- Log-only wiring from Stage 1 is removed from Jenkinsfile
- `docs/FUTURE_WORK.md` usage section reflects the new implementation
- `make test` passes
