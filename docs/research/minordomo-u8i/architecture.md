# Research: Claude Usage Check Architecture

## Current Implementation

`shared/check-usage.py` checks weekly Claude API utilization before launching agents.

### How It Works

1. Reads `CLAUDE_CODE_OAUTH_TOKEN` from environment
2. Reads `CLAUDE_ORG_ID` from environment (or uses `CLAUDE_USAGE_API_URL` override for tests)
3. Constructs URL: `https://claude.ai/api/organizations/{org_id}/usage`
4. Makes HTTP GET request with Bearer token auth
5. Parses `data["seven_day"]["utilization"]` from JSON response
6. Compares against `usage.weekly_threshold_pct` from `shared/config.yaml` (default 85)
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

## Decision: Use Claude CLI `/usage` Slash Command

Per GH issue #396 comments (wcjordan), the fix is to run `claude` interactively, send the
`/usage` slash command, and parse the output. The weekly utilization percentage IS available
from `/usage`:

```
Current week (all models)
█                                                  2% used
Resets Jun 21 at 8pm (America/New_York)
```

Parse target: the integer N on lines matching `N% used` that follow a `Current week` line.

## Container Environment (minordomo-image)

From `minordomo-container-builder/Dockerfile`:
- **Available:** `script` (util-linux >= 2.37, `-e` flag verified), `bash`, `python3`, Node.js
- **NOT available:** `expect`, `tcl`
- Claude Code CLI is installed at `/home/agent/.local/bin/claude`

## PTY Approach: Core Challenge

`script(1)` can allocate a PTY for `claude`, but two problems must be solved:
1. **Input timing:** `/usage` must be sent AFTER `claude` finishes starting up, or it arrives
   before the interactive prompt is ready and gets dropped/mishandled.
2. **Output capture:** `run-claude.sh` redirects to `/dev/null`; we need a file instead.

### Candidate Approach (worker should experiment):

```bash
OUTPUT=$(mktemp)
(sleep 3; printf '/usage\nexit\n'; sleep 3) | \
  script -q -e -c 'claude --dangerously-skip-permissions' "$OUTPUT" 2>&1 || true
# Then parse $OUTPUT for "Current week" section and "N% used"
rm -f "$OUTPUT"
```

The sleep durations are initial estimates — the worker should tune them based on observed
startup latency in the container. If timing proves unreliable, consider a loop that polls
the output file for the "Current week" line and kills the script process once found.

Output file will contain ANSI escape codes and box-drawing characters; parsing must handle
those (strip with `sed 's/\x1b\[[0-9;]*m//g'` or equivalent, then grep for `% used`).

## Jenkinsfile Log-Only Wiring (Stage 1)

To validate the approach in the real environment (Jenkins + Kubernetes + PTY), Stage 1
wires `fetch-claude-usage.sh` into Majordomo's Jenkinsfile in **log-only mode**: the script
runs alongside the existing `check-usage.py` call, its output is logged, but the result
does NOT gate execution. This lets the first post-Stage-1 Majordomo run produce observable
evidence that the PTY approach works (or what fails).

Majordomo runs every 30 minutes, so evidence appears quickly after a successful Majordomo
build that includes the Stage 1 changes.

## Files to Modify

- `shared/fetch-claude-usage.sh` (new) — PTY invocation, output capture, parsing
- `shared/check-usage.py` — Stage 2: replace HTTP API with call to `fetch-claude-usage.sh`
- `shared/config.yaml` — no change needed (threshold still applies)
- `majordomo/Jenkinsfile` — Stage 1: add log-only wiring; Stage 2: remove CLAUDE_ORG_ID,
  remove log-only wiring, make fetch-claude-usage.sh the gating check
- `test/bats/check-usage.bats` — Stage 2: update to mock `fetch-claude-usage.sh`
- `docs/FUTURE_WORK.md` — Stage 2: update usage section to reflect new implementation
