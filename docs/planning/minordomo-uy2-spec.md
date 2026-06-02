# Plan: Discord webhook url doesn't work

## Context

GH Issue #292. The `node shared/notify-pr-discord.js` call in majordomo and
agent pipelines prints `WARNING: DISCORD_WEBHOOK_URL is not set; skipping
Discord notification`. The webhook credential exists in Jenkins but either has
an empty value or the credential ID doesn't match.

There are two fixes:

1. **Operational** (out of scope for the worker): update the `discord-webhook-url`
   Jenkins credential with the real Discord webhook URL per
   `docs/setup/discord-webhook-setup.md`.

2. **Code** (in scope): `shared/agent-pipeline.Jenkinsfile` requires the Discord
   credential inside the main `withCredentials` block, so if the credential is
   absent from Jenkins the entire planning/worker build fails before Claude runs.
   This must be made truly optional. Additionally, `notify-pr-discord.js` should
   give clearer diagnostics so operators can distinguish a missing credential from
   an empty one.

---

## Stage 1: Make Discord credential optional in agent-pipeline.Jenkinsfile

### Description

Remove `string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK_URL')`
from the main `withCredentials([...])` block in `shared/agent-pipeline.Jenkinsfile`.

Extract the `node ../shared/notify-pr-discord.js /tmp/prompt-output.txt || true`
call out of the big sh block and place it in its own `script {}` block that wraps
it with an optional try-catch `withCredentials`. If the credential exists it fires
notifications; if it doesn't the catch logs a message and skips. The main Claude
work (and the rest of the build) is never blocked by the Discord credential.

Pattern to use inside the outer `withCredentials` scope:
```groovy
script {
    try {
        withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK_URL')]) {
            sh 'node ../shared/notify-pr-discord.js /tmp/prompt-output.txt || true'
        }
    } catch (e) {
        echo "Discord credential not configured; skipping PR notification"
    }
}
```

The large existing `sh """..."""` block has `node ../shared/notify-pr-discord.js`
as its last meaningful line before `exit $CLAUDE_EXIT`. Move that line out and
place the `script {}` block immediately after the `sh """..."""` block but still
inside the container/withCredentials scope. Keep `exit $CLAUDE_EXIT` inside the
`sh` block but move the notification out.

### Acceptance Criteria
- `shared/agent-pipeline.Jenkinsfile` no longer lists `discord-webhook-url` in
  the main `withCredentials` block.
- The notification call uses a try-catch `withCredentials` pattern inside a
  `script {}` block.
- Tests pass (`make test`).
- If the credential doesn't exist in Jenkins the build completes successfully
  (the try-catch catches the missing-credential exception and continues).

---

## Stage 2: Improve notify-pr-discord.js diagnostics and URL validation

### Description

Update `shared/notify-pr-discord.js` to give operators clearer guidance when
the webhook URL is not working:

1. Distinguish "not set" from "set but empty":
   - `process.env.DISCORD_WEBHOOK_URL === undefined` → "DISCORD_WEBHOOK_URL env
     var is not set"
   - `process.env.DISCORD_WEBHOOK_URL === ''` → "DISCORD_WEBHOOK_URL is set but
     empty — ensure the discord-webhook-url Jenkins credential has a valid value"

2. Validate the URL looks like a Discord webhook before attempting to use it:
   - Check that it starts with `https://discord.com/api/webhooks/` or
     `https://discordapp.com/api/webhooks/`
   - If it doesn't match: print a warning naming the actual value prefix (redact
     after first 30 chars) so operators can confirm what was injected.

These are all soft failures (exit 0) — the existing behavior of never breaking
builds is preserved.

### Acceptance Criteria
- Running the script with `DISCORD_WEBHOOK_URL` unset prints a message containing
  "not set".
- Running the script with `DISCORD_WEBHOOK_URL=""` prints a message containing
  "empty".
- Running the script with `DISCORD_WEBHOOK_URL=not-a-discord-url` prints a message
  containing "does not look like a Discord webhook URL".
- All three cases exit 0.
- Tests pass (`make test`).
