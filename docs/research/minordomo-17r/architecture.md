# Discord PR Notification — Research Notes

## Feature Summary
Send a Discord message whenever a PR is opened by minordomo.
Library specified: discord.js (Node.js).

## Codebase Context

### Container Image
- `minordomo-container-builder/Dockerfile` builds the shared agent image
- Node.js 22 is already installed; no npm packages installed yet
- Python deps in `minordomo-container-builder/requirements.txt` (boto3, pyyaml, requests)
- Container rebuilds on a weekly cron (`minordomo-container-builder/Jenkinsfile`)
- **Important**: Dockerfile changes don't take effect until the builder job runs

### Existing Notification Pattern
- `shared/notify-failure.py` — sends SES email on pipeline failure
  - Reads `NOTIFICATION_EMAIL`, `AWS_ACCESS_KEY_ID`, etc. from env
  - Exits 0 always (notification failures must not break builds)
- `vars/notifyFailure.groovy` — Jenkins shared library calling notify-failure.py

### PR Opening Points
Three places in the pipeline open PRs:

1. **Planning agent** (`minordomo-plan/system-prompt.md`):
   - Opens plan spec PR: task branch → feature branch
   - Run log step: `{"step": "open_pr", "status": "ok", "pr_url": "..."}`

2. **Worker agent** (`minordomo-step/system-prompt.md`):
   - Opens stage implementation PR: task branch → feature branch
   - Run log step: `{"step": "open_pr", "status": "ok", "pr_url": "..."}`

3. **Majordomo** (`majordomo/system-prompt.md` Step 9):
   - Opens feature→main PR after all stages are complete
   - Run log step: `{"step": "check_story_completion", "status": "ok", "epics_checked": N, "prs_opened": N, "epics_skipped": N}`
   - Step 9.l says "Capture stdout and log the PR URL" but the example doesn't include `pr_url` in the step summary

### Run Log Location
- All agents output `--output-format json` to `/tmp/claude-output.json`
- The run log JSON is in the `result` field (as a markdown-fenced code block)
- `shared/report-token-usage.py` extracts it to stdout → `/tmp/prompt-output.txt`

### Jenkinsfile Structure
- Planning/worker agents share `shared/agent-pipeline.Jenkinsfile`
  - Credentials: `claude-code-oauth-token`, `github-app`
  - Calls claude then report-token-usage
- Majordomo uses `majordomo/Jenkinsfile` (standalone)

## Design Decisions Pending

### Scope Question (NEEDS HUMAN INPUT)
"Whenever a PR is opened by minordomo" is ambiguous:
- **All PRs**: plan spec PR + N stage PRs + feature→main PR = ~5+ notifications per epic
- **Feature→main only**: just the PR humans actually review and merge (~1 per epic)

This materially changes the implementation:
- All PRs → wire into `agent-pipeline.Jenkinsfile` (covers planning + worker) AND majordomo
- Feature→main only → wire only into `majordomo/Jenkinsfile`

### Credential Design
- Discord Webhook URL is simplest: single env var `DISCORD_WEBHOOK_URL`
- No bot needed; Discord webhook supports direct HTTP POST
- discord.js `WebhookClient` accepts a webhook URL directly
- Pattern: if `DISCORD_WEBHOOK_URL` not set, exit 0 with warning (same as notify-failure.py)

### Container Build Gap
- If we add discord.js to the Dockerfile, it won't be available until the builder job fires
- Stage 1 acceptance criteria should include manually triggering the builder job
- OR the script should gracefully handle `Cannot find module 'discord.js'` at runtime

### Majordomo PR URL in Run Log
- The majordomo system prompt says to "log the PR URL" in step 9 but the example JSON doesn't include `pr_url` in the step schema
- If wiring majordomo notifications, the system prompt may need updating to emit `pr_url` explicitly
