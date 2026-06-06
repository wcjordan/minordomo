# Plan: Post a Message to Discord Whenever Human Input Is Requested

## Overview

When the planning agent asks a question and triggers the Questions Path, it resets its beads task and exits 0 — but nothing notifies the human to go look at the GitHub issue. This feature adds a Discord notification at that moment.

**Scope**: Both the planning agent's Questions Path and the worker's Needs Input Flow call `shared/apply-needs-input.sh`, so adding the notification there covers both paths for free.

**Discord message format**: `"Human input requested: <gh_issue_url>"`

---

## Stage 1: Extract shared Discord sender and refactor notify-pr-discord.js to use it

### Description

Extract a minimal `shared/discord-send.js` script that accepts a message as its first CLI argument and posts it to the Discord webhook URL from `DISCORD_WEBHOOK_URL`. It must mirror the existing validation and graceful-exit-on-missing-webhook behaviour from `notify-pr-discord.js`.

Refactor `notify-pr-discord.js` to call `discord-send.js` for the actual send step instead of instantiating `WebhookClient` inline.

Add bats tests in `test/bats/discord-send.bats` covering:
- Sends message to webhook when `DISCORD_WEBHOOK_URL` is set and argument is provided
- Exits 0 and emits a warning when `DISCORD_WEBHOOK_URL` is unset
- Exits 0 and emits a warning when `DISCORD_WEBHOOK_URL` is empty
- Exits 0 and emits a warning when `DISCORD_WEBHOOK_URL` does not start with a valid Discord prefix

Update `test/bats/notify-pr-discord.bats` to stub `discord-send.js` rather than `WebhookClient`, and verify all existing tests continue to pass.

### Acceptance Criteria

- `shared/discord-send.js <message>` exists and posts `<message>` to the Discord webhook
- `notify-pr-discord.js` no longer instantiates `WebhookClient` directly; all webhook sends route through `discord-send.js`
- New `discord-send.bats` tests are added and pass
- All existing `notify-pr-discord.bats` tests continue to pass
- `make test` passes

---

## Stage 2: Inject DISCORD_WEBHOOK_URL into agent container and add notification to apply-needs-input.sh

### Description

Two changes:

**Jenkinsfile** (`shared/agent-pipeline.Jenkinsfile`): Wrap the main agent `sh` block with a best-effort `withCredentials` for the `discord-webhook-url` credential, injecting `DISCORD_WEBHOOK_URL` into the agent container's environment. Use the same try/catch pattern as the existing `notify-pr-discord.js` step so that a missing credential is silently skipped rather than failing the build.

**apply-needs-input.sh**: After the three required steps (label, comment, beads reset) succeed, call `node "${SCRIPT_DIR}/discord-send.js" "Human input requested: https://github.com/wcjordan/${repo}/issues/${issue_number}"` as a best-effort step (`|| true`). The notification must fire only after all three required steps complete so a webhook failure cannot interrupt the needs-input protocol.

Add bats tests in `test/bats/apply-needs-input.bats` covering:
- Sends Discord notification when `DISCORD_WEBHOOK_URL` is set and all three steps succeed
- Does not fail (exits 0) when `DISCORD_WEBHOOK_URL` is unset
- The three required steps (label, comment, beads reset) run even when Discord send fails

### Acceptance Criteria

- `shared/agent-pipeline.Jenkinsfile` injects `DISCORD_WEBHOOK_URL` into the agent `sh` block with best-effort credential handling
- `apply-needs-input.sh` calls `discord-send.js` with `"Human input requested: <gh_issue_url>"` after the three required steps
- A Discord webhook failure does not cause `apply-needs-input.sh` to exit non-zero
- New `apply-needs-input.bats` tests for the Discord notification case are added and pass
- `make test` passes
