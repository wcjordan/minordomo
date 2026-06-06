# Research: Discord Notifications for Human Input Requests

## Feature Goal

Post a Discord message whenever human input is requested — covering both the planning agent's Questions Path and the worker's Needs Input Flow.

## How Human Input Is Requested

Two paths trigger needs-input:

### Planning Agent Questions Path (`minordomo-plan/system-prompt.md`)
- Calls `shared/apply-needs-input.sh` with the GH issue number, beads task ID, and questions
- Emits a run log step: `{"step": "beads_status_update", "status": "ok", "new_status": "open", "reason": "needs_input"}`
- Run log status is `"success"` (not a failure, just pending input)
- The `gh_issue_url` is NOT currently included in this step

### Worker Needs Input Flow (`minordomo-step/system-prompt.md`)
- Calls `shared/apply-needs-input.sh` similarly
- Emits `"commit_partial"` and `"beads_reset"` steps
- Run log status is `"failure"` with errors
- No specific step identifies this as a needs-input case (vs. a crash)
- GH issue URL is NOT currently included in the run log

## Existing Discord Notification Mechanism

`shared/notify-pr-discord.js`:
- Runs post-agent in the Jenkinsfile (separate `sh` step)
- Receives `DISCORD_WEBHOOK_URL` via Groovy string interpolation (not available during agent execution)
- Parses the run log JSON from `/tmp/prompt-output.txt`
- Only triggers on `pr_url` or `pr_urls` fields in run log steps
- Uses `discord.js` WebhookClient

## Key Constraint: DISCORD_WEBHOOK_URL Not Available During Agent Execution

The Jenkinsfile only injects `DISCORD_WEBHOOK_URL` for the `notify-pr-discord.js` step, not for the agent's `sh` block. So `apply-needs-input.sh` cannot post to Discord directly without a Jenkinsfile change.

## Implementation Approach

The cleanest implementation uses the existing post-agent notification pattern:

1. **Update `notify-pr-discord.js`** to detect needs-input signals in the run log:
   - Planning agent: detect `beads_status_update` step with `reason: "needs_input"` + `gh_issue_url`
   - Worker: detect a new `needs_input` step type with `gh_issue_url`
   - Message: `"Human input requested: <gh_issue_url>"`

2. **Update planning agent system prompt** to include `gh_issue_url` in the `beads_status_update` step

3. **Update worker system prompt** to emit a `{"step": "needs_input", "gh_issue_url": "..."}` step in the Needs Input Flow

## Files to Change

- `shared/notify-pr-discord.js` — add needs-input detection
- `test/bats/notify-pr-discord.bats` — add tests for needs-input case
- `minordomo-plan/system-prompt.md` — add `gh_issue_url` to `beads_status_update` step
- `minordomo-step/system-prompt.md` — add `needs_input` step to Needs Input Flow
