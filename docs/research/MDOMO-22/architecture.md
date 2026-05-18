# MDOMO-22 Research: Measure Claude Token Usage by Job

## Goal

Track token usage per job type (majordomo, plan, step) to estimate orchestration overhead.

## How Claude Is Invoked

All three job types invoke Claude identically in their Jenkinsfiles:

```bash
claude -p "$(cat <job>/system-prompt.md)"
```

| Job | Jenkinsfile | Claude invocation line |
|-----|------------|----------------------|
| Majordomo | `majordomo/Jenkinsfile:51` | `claude -p "$(cat majordomo/system-prompt.md)"` |
| Planning Agent | `minordomo-plan/Jenkinsfile:54` | `claude -p "$(cat ../minordomo-plan/system-prompt.md)"` |
| Worker | `minordomo-step/Jenkinsfile:54` | `claude -p "$(cat ../minordomo-step/system-prompt.md)"` |

No `--output-format` or `--verbose` flags are currently used.

## Claude CLI `--output-format json` Output

Running `claude -p --output-format json "..."` produces a JSON object on stdout with this structure:

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 12345,
  "duration_api_ms": 11000,
  "num_turns": 42,
  "result": "<agent text output as a string>",
  "total_cost_usd": 0.1234,
  "usage": {
    "input_tokens": 50000,
    "cache_creation_input_tokens": 5000,
    "cache_read_input_tokens": 40000,
    "output_tokens": 3000,
    "service_tier": "standard"
  }
}
```

The `result` field contains whatever the agent emitted to stdout (i.e., the agent's JSON run log). This is the key mechanism for extracting token counts.

## Current Token Tracking

None. No token counting, cost tracking, or metrics infrastructure exists.

## Existing Logging Infrastructure

- **Jenkins build logs**: Each job's stdout is captured by Jenkins (build history only, no aggregation)
- **No metrics backend**: No Prometheus, Datadog, CloudWatch, or database
- **Agent run logs**: Agents emit structured JSON to stdout (step-by-step status), but no token fields

## Stage 5 Notes (future, unrelated)

`shared/config.yaml` has a `usage.weekly_threshold_pct` field (currently not enforced). Stage 5 would check `https://api.anthropic.com/api/oauth/usage` against this threshold. That's account-level rate limiting, not per-job measurement. MDOMO-22 is about per-job measurement.

## Implementation Approach

1. Add `--output-format json` to Claude invocations in all three Jenkinsfiles
2. Capture the JSON to a temp file, preserving the original exit code
3. Parse the JSON with a shared Python script (`shared/report-token-usage.py`) to print a human-readable token summary in the Jenkins log

This approach:
- Requires no new infrastructure
- Integrates with existing Jenkins build log workflow
- Preserves all existing exit-code behavior
- Shows usage per build, per job type, directly in the build log

## File Paths

- `majordomo/Jenkinsfile` — majordomo Claude invocation
- `minordomo-plan/Jenkinsfile` — planning agent Claude invocation
- `minordomo-step/Jenkinsfile` — worker agent Claude invocation
- `shared/config.yaml` — has unused `usage` block (Stage 5)
- `docs/agent-workflow-spec.md` — Stage 5 usage check spec (reference)
- `test/bats/` — bats test directory
- `test/fixtures/` — test fixture JSON files
