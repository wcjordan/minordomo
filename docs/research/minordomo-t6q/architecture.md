# Research: discord.js Module Not Available

## Root Cause

The current `minordomo-image:latest` container does not have `discord.js` installed
and `NODE_PATH` is not set. Confirmed by:
- `echo $NODE_PATH` → not set
- `ls /opt/discord-notify/node_modules` → no such directory

The Dockerfile (`minordomo-container-builder/Dockerfile`) was updated in PR #285 to install
discord.js at `/opt/discord-notify/node_modules` and set `NODE_PATH`. However, the container
image rebuild only runs on Sundays (weekly cron), so the running image predates that Dockerfile
change.

## The Graceful Fallback

`shared/notify-pr-discord.js` has a `try/catch` around `require('discord.js')` (added in PR #302)
that emits a warning and exits 0 if the module is not found. This prevents pipeline failures but
means Discord notifications are silently skipped.

## Affected Pipelines

The issue mentions "likely an issue in other pipelines as well" — any pipeline using
`shared/agent-pipeline.Jenkinsfile` is affected (both `minordomo-plan` and `minordomo-step`).

## Preferred Fix: Remove discord.js Dependency

Replace discord.js with Node.js 22 built-in `fetch()` API to POST directly to the Discord webhook
endpoint. This eliminates the external npm dependency entirely, making the script self-sufficient
regardless of container image state.

### Discord Webhook API
Simple HTTP POST to the webhook URL with JSON body: `{"content": "message text"}`.

### Testing Strategy
Current tests use `NODE_PATH="$STUB_DIR"` to inject a stub discord.js module.
After removing the discord.js dependency, use a `DISCORD_STUB_OUT` env var directly in the script
(write to file when set, send real HTTP otherwise). Tests already set `DISCORD_STUB_OUT`; they just
need the `NODE_PATH` removed and the stub file deleted.

## Files Involved

- `shared/notify-pr-discord.js` — main script to modify
- `test/bats/notify-pr-discord.bats` — tests to update
- `test/fixtures/discord-stub/discord.js` — stub to delete (no longer needed)
- `minordomo-container-builder/Dockerfile` — cleanup (remove discord.js npm install + NODE_PATH)

## Container Rebuild Note

After Dockerfile cleanup, the container needs to be rebuilt. The builder runs weekly on Sundays.
For immediate effect, the `minordomo-container-builder` Jenkins job can be triggered manually.
