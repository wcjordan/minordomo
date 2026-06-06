# Implementation Plan: minordomo-t6q — Fix discord.js module not available

## Background

`shared/notify-pr-discord.js` uses the `discord.js` npm package to send webhook
notifications. The `minordomo-image:latest` container does not have `discord.js`
installed (confirmed: `NODE_PATH` is unset, `/opt/discord-notify/node_modules` does
not exist). The container-builder Dockerfile was updated in PR #285 to install it,
but the image has not been rebuilt since then (builder runs weekly on Sundays).

The fix removes the `discord.js` dependency entirely and replaces it with Node.js 22's
built-in `fetch()` API to POST directly to the Discord webhook endpoint. This is
self-sufficient regardless of container image state and eliminates the external npm
dependency. The Dockerfile install is removed as dead code.

---

## Stage 1: Replace discord.js with native fetch and remove dead Dockerfile dependency

### Description

Replace the `discord.js` npm dependency in `shared/notify-pr-discord.js` with Node.js
22's built-in `fetch()` API. Discord webhooks are plain HTTP `POST` requests — no SDK
required. Add `DISCORD_STUB_OUT` support directly in the script for test stubbing (the
tests already set this env var). Remove the now-unused discord.js stub fixture and
clean up the `minordomo-container-builder/Dockerfile`.

#### Changes required

**`shared/notify-pr-discord.js`**:
- Remove the `try/catch` block that attempts `require('discord.js')` and the
  `WebhookClient` variable
- Replace the `(async () => { ... })()` send loop with a loop that calls a local
  `sendWebhook(url, content)` async function
- `sendWebhook` implementation:
  - If `process.env.DISCORD_STUB_OUT` is set, `fs.appendFileSync(stubOut, content + '\n')` and return (test stub path)
  - Otherwise, `await fetch(webhookUrl, { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({content}) })`
  - Wrap the `fetch()` call in `try/catch`; on error, emit a `WARNING:` to stderr and continue (do not crash)

**`test/bats/notify-pr-discord.bats`**:
- Remove `STUB_DIR` variable from `setup()` (the fixture directory is no longer needed)
- Remove `NODE_PATH="$STUB_DIR"` from every test that sets it
- Delete the test `"exits 0 with warning when discord.js is unavailable"` — it tests
  behaviour that no longer exists (the try/catch for require)
- All other tests continue to work because they already set `DISCORD_STUB_OUT`

**`test/fixtures/discord-stub/discord.js`**: delete this file

**`minordomo-container-builder/Dockerfile`**:
- Remove the `discord.js` npm install block:
  ```
  # discord.js — used by shared/notify-pr-discord.js for PR notifications
  RUN mkdir -p /opt/discord-notify && \
      printf '...' > /opt/discord-notify/package.json && \
      npm install --prefix /opt/discord-notify --omit=dev
  ENV NODE_PATH=/opt/discord-notify/node_modules
  ```

Do NOT trigger a container rebuild — the script fix is self-contained and works
immediately without any image change.

### Acceptance Criteria
- `make test` passes (shellcheck, bats suite, validate-prompts, dry-run, check-safety)
- `node shared/notify-pr-discord.js` no longer attempts to `require('discord.js')`
- Running the script with a valid `DISCORD_WEBHOOK_URL` and `DISCORD_STUB_OUT` set
  writes the expected `New PR opened: <url>` line to the stub output file
- Running the script with a valid `DISCORD_WEBHOOK_URL` but no `DISCORD_STUB_OUT`
  attempts a real `fetch()` to the webhook URL (graceful error if unreachable)
- The `minordomo-container-builder/Dockerfile` no longer contains the discord.js
  npm install block or the `NODE_PATH` env var
- `test/fixtures/discord-stub/discord.js` no longer exists
