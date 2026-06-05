# Research: Discord webhook env var in majordomo Jenkinsfile

## Problem

The `majordomo/Jenkinsfile` declares `DISCORD_WEBHOOK_URL` in its `environment {}` block,
but the call to `notify-pr-discord.js` is inside a `sh ''' ... '''` block (single-quoted,
no Groovy interpolation). When running inside a Kubernetes container step, env vars injected
via the `environment {}` block (and via `withCredentials`) do not reliably propagate into the
container process via the Kubernetes plugin's remoting layer.

The comment in `shared/agent-pipeline.Jenkinsfile` documents this exact issue:
> Use Groovy interpolation to explicitly pass the value to the container process.
> withCredentials inside container() does not reliably inject env vars via the Kubernetes
> plugin's remoting layer; interpolation bypasses this.

## Current state

### `shared/agent-pipeline.Jenkinsfile` (working fix already applied)
```groovy
script {
    try {
        withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK_URL')]) {
            sh "DISCORD_WEBHOOK_URL='${DISCORD_WEBHOOK_URL}' node shared/notify-pr-discord.js /tmp/prompt-output.txt || true"
        }
    } catch (e) {
        echo "Discord credential not configured; skipping PR notification"
    }
}
```

### `majordomo/Jenkinsfile` (broken)
- `DISCORD_WEBHOOK_URL` is declared in the `environment { }` stage block
- The call is inside the long `sh ''' ... '''` block:
  `node shared/notify-pr-discord.js /tmp/prompt-output.txt || true`
- No Groovy interpolation → env var not reliably passed into container process

## Fix

Move the `notify-pr-discord.js` call out of the main `sh ''' ... '''` block and into a
separate `script {}` block using Groovy string interpolation (double-quoted `sh "..."`)
to explicitly bake `DISCORD_WEBHOOK_URL` into the shell command, bypassing the remoting
layer issue.

The `environment { DISCORD_WEBHOOK_URL = credentials(...) }` block can remain as-is — it
makes the credential available as a Groovy variable. The `script {}` block then uses
`"DISCORD_WEBHOOK_URL='${DISCORD_WEBHOOK_URL}' node ..."` to pass it explicitly.

## Story PR notifications

`shared/notify-pr-discord.js` already handles `pr_urls` arrays in step objects:
```js
if (Array.isArray(step.pr_urls)) {
  prUrls.push(...step.pr_urls);
}
```

The majordomo system-prompt Step 9 emits `pr_urls` in the `check_story_completion` step,
so story PR notifications will work correctly once the env var is reliably passed.
No changes needed to `notify-pr-discord.js` or the system-prompt for this.
