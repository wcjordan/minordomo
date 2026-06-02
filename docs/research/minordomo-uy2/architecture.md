# Discord Webhook URL Bug — Research Notes

## Issue
GH #292: `node shared/notify-pr-discord.js /tmp/prompt-output.txt` prints
`WARNING: DISCORD_WEBHOOK_URL is not set; skipping Discord notification`

## Root Cause Analysis

### The notification script (shared/notify-pr-discord.js)
- Reads `process.env.DISCORD_WEBHOOK_URL`
- If falsy (undefined or empty string): prints warning, exits 0 (no failure)
- Already handles missing credential gracefully

### Where credentials are injected

**majordomo/Jenkinsfile** (declarative pipeline):
```groovy
environment {
    DISCORD_WEBHOOK_URL = credentials('discord-webhook-url')
}
```
If the `discord-webhook-url` credential doesn't exist in Jenkins, declarative
pipelines silently set the variable to empty string in some Jenkins versions.
That matches the observed behavior: build runs, notification script prints
the warning.

**shared/agent-pipeline.Jenkinsfile** (scripted-style in try/catch):
```groovy
withCredentials([
    ...
    string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK_URL'),
]) {
    ...
}
```
If the credential doesn't exist, `withCredentials` throws an exception and
**fails the entire build** — including the Claude agent work. This is a code
bug: Discord credential is treated as required when it should be optional.

### Setup scripts don't clobber the variable
Checked `shared/setup-env.sh`, `shared/setup-claude.sh`, `shared/bootstrap.sh`:
none uses `unset`, `env -i`, or touches DISCORD_WEBHOOK_URL. Env clobbering
is ruled out as root cause.

## Two-Part Fix Needed

1. **Operational (not code)**: The `discord-webhook-url` Jenkins credential needs
   to be populated with a real Discord webhook URL.

2. **Code bug**: `shared/agent-pipeline.Jenkinsfile` must not hard-require the
   Discord credential in the main `withCredentials` block. If the credential is
   missing, the entire planning/worker build fails — that's wrong. The notification
   is already supposed to be optional (the `|| true` on the script call was meant
   for this, but the `withCredentials` binding fails first).

## Log Evidence
The warning comes from the majordomo pipeline (path without `../` prefix):
```
+ node shared/notify-pr-discord.js /tmp/prompt-output.txt
WARNING: DISCORD_WEBHOOK_URL is not set; skipping Discord notification
```
The agent pipeline would show a different error (withCredentials failure) if
the credential truly doesn't exist. The majordomo log showing the script run
confirms: credential exists in Jenkins but has empty/wrong value.

## Files to Change
- `shared/agent-pipeline.Jenkinsfile` — move Discord credential out of required
  `withCredentials` block; use try-catch optional pattern
- `shared/notify-pr-discord.js` — improve warning to distinguish "not set" vs
  "set but empty", and validate URL format so operators get clearer guidance
