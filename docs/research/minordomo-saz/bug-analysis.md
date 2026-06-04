# Bug Analysis: notify-pr-discord.js path in agent-pipeline.Jenkinsfile

## Root Cause

In `shared/agent-pipeline.Jenkinsfile` line 81, `notify-pr-discord.js` is called with a `../` prefix:

```groovy
sh "DISCORD_WEBHOOK_URL='${DISCORD_WEBHOOK_URL}' node ../shared/notify-pr-discord.js /tmp/prompt-output.txt || true"
```

This `sh` step is a **separate** Groovy `sh` call (inside a `script {}` block), so it runs from the Jenkins workspace root (e.g., `/home/jenkins/agent/workspace/minordomo-plan_main/`). The `../` goes up one level above the workspace root, producing the path `/home/jenkins/agent/workspace/shared/notify-pr-discord.js` — which does not exist.

## Why `../` is correct in line 72 but not line 81

Line 72 is inside the main `sh` block (lines 62–74) where `source shared/bootstrap.sh` runs `setup-workspace.sh`, which calls `cd "${REPO}"`. After that `cd`, the CWD is the cloned target repo subdirectory (e.g., `/home/jenkins/agent/workspace/minordomo-plan_main/minordomo/`). From there, `../shared/` correctly points back to the workspace root's `shared/` directory.

Line 81 is a **separate** `sh` step. Jenkins resets the CWD to the workspace root for each `sh` step. The `cd` from the first `sh` block does not carry over. So from the workspace root, `../shared/` goes above the workspace, not into it.

## Fix

Change line 81 from:
```
node ../shared/notify-pr-discord.js
```
to:
```
node shared/notify-pr-discord.js
```

This matches how `majordomo/Jenkinsfile` line 84 calls the same script from its workspace root: `node shared/notify-pr-discord.js`.

## Affected Files

- `shared/agent-pipeline.Jenkinsfile` line 81 — the only change needed
