# minordomo-17r: Send a message to Discord whenever a PR is opened

## Overview

Add a Discord webhook notification whenever minordomo opens a PR. This covers all three PR-opening points: planning agent (plan spec PR), worker agent (stage implementation PRs), and Majordomo (feature→main PR). The feature uses discord.js `WebhookClient` to post to a configurable Discord webhook URL.

---

## Stage 1: Add discord.js to container and create PR notification script

### Description

Install discord.js in the minordomo container image and create `shared/notify-pr-discord.js`, the shared notification script. The script reads a run-log file (`/tmp/prompt-output.txt`), extracts any `pr_url` values from `steps[].pr_url` and `steps[].pr_urls[]` arrays, and sends a Discord message for each PR URL found via a webhook.

Pattern follows `shared/notify-failure.py`:
- If `DISCORD_WEBHOOK_URL` env var is unset, print a warning to stderr and exit 0.
- Wrap the discord.js `require` in a try/catch so that if the module is not yet installed (old container still deployed), it prints a warning and exits 0. This prevents build failures during the container-build gap.
- Notification failures must not break the build; all paths exit 0.

JSON extraction follows the two-pass approach in `shared/check-run-errors.py`:
1. Find the first ` ```json ` code block in the file and parse it as the run log.
2. Fall back to the last parseable JSON line.

Discord message format (one message per PR URL):
```
New PR opened: <pr_url>
```

Add bats tests under `test/bats/notify-pr-discord.bats` using `NODE_PATH` pointing to a fixture directory with a stub `discord.js` module that records calls.

**Dockerfile change:** Add a `RUN` layer to `minordomo-container-builder/Dockerfile` that installs discord.js v14 into `/opt/discord-notify/`:
```dockerfile
RUN mkdir -p /opt/discord-notify && \
    printf '{"name":"discord-notify","version":"1.0.0","dependencies":{"discord.js":"^14.16.3"}}' \
        > /opt/discord-notify/package.json && \
    npm install --prefix /opt/discord-notify --omit=dev
ENV NODE_PATH=/opt/discord-notify/node_modules
```

After this stage merges to the feature branch, manually trigger the `minordomo-container-builder` Jenkins job and verify it completes successfully before proceeding to Stage 3.

### Acceptance Criteria
- `minordomo-container-builder/Dockerfile` installs discord.js v14 into `/opt/discord-notify/` and sets `NODE_PATH`
- `shared/notify-pr-discord.js` exists and is executable
- Script reads run-log path from `argv[2]` (matches the `node script.js <path>` call pattern)
- Script extracts `pr_url` from `steps[].pr_url` fields in the run log JSON
- Script extracts items from `steps[].pr_urls` array fields (for Majordomo's multi-PR step)
- Script sends one Discord message per PR URL found using `discord.js` `WebhookClient`
- If `DISCORD_WEBHOOK_URL` is unset, script prints warning to stderr and exits 0
- If `discord.js` module is unavailable (try/catch), script prints warning to stderr and exits 0
- If run-log file is missing or unparseable, script exits 0 with warning (notification failures must not break builds)
- `test/bats/notify-pr-discord.bats` covers: URL sent, no-URL (no-op), missing env var, missing file, discord.js unavailable
- `make test` passes

---

## Stage 2: Update Majordomo run log to emit pr_urls in check_story_completion step

### Description

Update `majordomo/system-prompt.md` so that Step 9 emits the URL of each opened PR into the run log. Currently, Step 9.l says "Capture stdout and log the PR URL" but the `check_story_completion` step schema has no `pr_urls` field. Add `pr_urls: [...]` to the step — an array containing the URL of every PR opened in that run.

Changes required:
- In Step 9.l: after opening the PR, append its URL to a local `opened_pr_urls` list.
- In Step 9 result logging (sub-step 3): include `pr_urls` array alongside existing fields.
- Update the run log format section's `check_story_completion` example to include `"pr_urls": ["https://..."]`.

### Acceptance Criteria
- `majordomo/system-prompt.md` Step 9.l accumulates PR URLs into `opened_pr_urls`
- Step 9 result log includes `"pr_urls": [...]` (empty array if no PRs opened)
- Run log format section example shows `"pr_urls"` in `check_story_completion`
- `make test` passes (prompt validation script must accept the updated format)

---

## Stage 3: Wire Discord notifications into Jenkinsfiles and add credential

### Description

Call `notify-pr-discord.js` after each agent run in both Jenkinsfiles, binding the `DISCORD_WEBHOOK_URL` credential.

**`shared/agent-pipeline.Jenkinsfile`** — in the `withCredentials` block, add the `discord-webhook-url` credential binding. After the `python3 ../shared/report-token-usage.py ...` line, add:
```groovy
node ../shared/notify-pr-discord.js /tmp/prompt-output.txt || true
```

**`majordomo/Jenkinsfile`** — in the `DISCORD_WEBHOOK_URL = credentials('discord-webhook-url')` environment block for the Majordomo stage. After the `python3 shared/report-token-usage.py ...` line (inside the `sh` block), add:
```sh
node shared/notify-pr-discord.js /tmp/prompt-output.txt || true
```

Both calls use `|| true` so that any script failure (missing credential, network error, unexpected exception) never fails the build.

**Prerequisite (out-of-band, not automated):** A Jenkins credential of type "Secret text" named `discord-webhook-url` containing the Discord webhook URL must be created before notifications will fire. If the credential is absent Jenkins will fail to inject it — gate this on the credential existing first. Document this prereq in a comment in the Jenkinsfile near the credential binding.

### Acceptance Criteria
- `shared/agent-pipeline.Jenkinsfile` binds `DISCORD_WEBHOOK_URL` from `discord-webhook-url` Jenkins credential
- `shared/agent-pipeline.Jenkinsfile` calls `node ../shared/notify-pr-discord.js /tmp/prompt-output.txt || true` after report-token-usage
- `majordomo/Jenkinsfile` binds `DISCORD_WEBHOOK_URL` from `discord-webhook-url` Jenkins credential in the Majordomo stage environment block
- `majordomo/Jenkinsfile` calls `node shared/notify-pr-discord.js /tmp/prompt-output.txt || true` after report-token-usage in the Majordomo stage sh block
- Both calls are outside any `exit $CLAUDE_EXIT` / `exit` call — i.e., they execute after the agent but before exiting the shell block
- Comment near each credential binding notes the out-of-band prereq
- `make test` passes
