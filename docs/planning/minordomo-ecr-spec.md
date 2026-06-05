# Implementation Plan: Pass Discord Webhook Env Var to Notify Discord Script (Majordomo)

## Background

The `shared/agent-pipeline.Jenkinsfile` (used by plan and worker pipelines) already correctly
passes `DISCORD_WEBHOOK_URL` to `notify-pr-discord.js` via Groovy string interpolation,
bypassing a known Kubernetes plugin env-injection issue. The `majordomo/Jenkinsfile` has the
credential in its `environment {}` block but calls `notify-pr-discord.js` from inside a
single-quoted `sh ''' ... '''` block where Groovy interpolation doesn't occur, so the env
var is not reliably passed to the container process.

---

## Stage 1: Fix Discord webhook env var injection in majordomo Jenkinsfile

### Description

Move the `node shared/notify-pr-discord.js` call out of the main `sh ''' ... '''` block in
`majordomo/Jenkinsfile` and into a separate `script {}` block that uses Groovy string
interpolation (`"DISCORD_WEBHOOK_URL='${DISCORD_WEBHOOK_URL}' node ..."`) to explicitly
pass the credential value to the container process, matching the pattern already used in
`shared/agent-pipeline.Jenkinsfile`.

The `environment { DISCORD_WEBHOOK_URL = credentials('discord-webhook-url') }` block stays,
making the value available as a Groovy binding. The fix wraps the notification call in a
`try/catch` so a missing or unconfigured credential degrades gracefully (matching
agent-pipeline.Jenkinsfile's pattern).

No changes are needed to `notify-pr-discord.js` or the majordomo system-prompt — the notify
script already handles the `pr_urls` array format emitted by Step 9 (`check_story_completion`),
so story PRs to main will be notified once the env var is reliably injected.

### Acceptance Criteria

- `majordomo/Jenkinsfile` no longer calls `node shared/notify-pr-discord.js` from inside the
  long `sh ''' ... '''` block.
- A new `script {}` block after the main `sh` block calls the notify script via Groovy string
  interpolation: `"DISCORD_WEBHOOK_URL='${DISCORD_WEBHOOK_URL}' node shared/notify-pr-discord.js /tmp/prompt-output.txt || true"`.
- The call is wrapped in a `try/catch` that prints a warning and continues if the
  `discord-webhook-url` credential is absent (no build failure).
- `make test` passes (shellcheck + bats + prompt validation).
