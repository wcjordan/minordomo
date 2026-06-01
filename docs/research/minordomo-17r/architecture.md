# Discord PR Notification — Research Notes

## Feature Summary
Send a Discord message whenever a PR is opened by minordomo (all PRs — per owner clarification on GH issue #273 comment).
Library specified: discord.js (Node.js), using `WebhookClient`.

## Codebase Context

### Container Image
- `minordomo-container-builder/Dockerfile` builds the shared agent image
- Node.js 22 is already installed; no npm packages installed yet
- Python deps in `minordomo-container-builder/requirements.txt` (boto3, pyyaml, requests)
- Container rebuilds on a weekly cron (`minordomo-container-builder/Jenkinsfile`)
- **Important**: Dockerfile changes don't take effect until the builder job runs
- **Gap mitigation**: `notify-pr-discord.js` wraps `require('discord.js')` in try/catch to exit 0 with warning if module not yet installed

### Existing Notification Pattern
- `shared/notify-failure.py` — sends SES email on pipeline failure
  - Reads `NOTIFICATION_EMAIL`, `AWS_ACCESS_KEY_ID`, etc. from env
  - Exits 0 always (notification failures must not break builds)
  - Same pattern to follow for Discord script
- `vars/notifyFailure.groovy` — Jenkins shared library calling notify-failure.py

### PR Opening Points (all three targeted — "all PRs" confirmed by owner)
Three places in the pipeline open PRs:

1. **Planning agent** (`minordomo-plan/system-prompt.md`):
   - Opens plan spec PR: task branch → feature branch
   - Run log step: `{"step": "open_pr", "status": "ok", "pr_url": "..."}`

2. **Worker agent** (`minordomo-step/system-prompt.md`):
   - Opens stage implementation PR: task branch → feature branch
   - Run log step: `{"step": "open_pr", "status": "ok", "pr_url": "..."}`

3. **Majordomo** (`majordomo/system-prompt.md` Step 9):
   - Opens feature→main PR after all stages are complete
   - Current run log step lacks pr_url — Stage 2 adds `pr_urls: [...]` to `check_story_completion`

### Run Log Location
- All agents output `--output-format json` to `/tmp/claude-output.json`
- The run log JSON is in the `result` field (as a markdown-fenced code block)
- `shared/report-token-usage.py` extracts it to stdout → `/tmp/prompt-output.txt`
- `shared/check-run-errors.py` parses the same file using two-pass: JSON code block, then last JSON line
- `notify-pr-discord.js` follows the same parsing pattern

### Jenkinsfile Structure & CWD Behavior
- Planning/worker agents share `shared/agent-pipeline.Jenkinsfile`
  - After `source shared/bootstrap.sh`, CWD is the TARGET REPO clone (e.g. `minordomo/`)
  - Scripts from minordomo are at `../shared/` relative to that CWD
  - Call: `node ../shared/notify-pr-discord.js /tmp/prompt-output.txt || true`
- Majordomo uses `majordomo/Jenkinsfile` (standalone)
  - No target-repo clone; CWD stays at Jenkins workspace root
  - Call: `node shared/notify-pr-discord.js /tmp/prompt-output.txt || true`

### discord.js Installation
- Install into `/opt/discord-notify/` in Dockerfile via `npm install --prefix`
- Set `ENV NODE_PATH=/opt/discord-notify/node_modules` so `require('discord.js')` works
- Use `WebhookClient` from discord.js v14

### Jenkins Credential
- Credential name: `discord-webhook-url` (type: Secret text)
- Bound as `DISCORD_WEBHOOK_URL` env var
- If unset: script exits 0 with warning (same as `NOTIFICATION_EMAIL` in notify-failure.py)
- Out-of-band prereq: credential must be created in Jenkins before notifications fire

## Design Decisions

### Scope: All PRs (confirmed by owner)
"Whenever a PR is opened by minordomo" = all PRs:
- Planning spec PR + N stage PRs + feature→main PR (~5+ per epic)

### Module Loading
- discord.js wraps in try/catch for graceful degradation during container-build gap
- `|| true` on Jenkinsfile call ensures notification failures never break builds

### Message Format
```
New PR opened: <pr_url>
```
Simple URL post; Discord auto-embeds the PR preview.
