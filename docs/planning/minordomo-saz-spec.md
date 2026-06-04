# Implementation Plan: minordomo-saz

Fix `notify-pr-discord.js` failing in `minordomo-plan` due to incorrect relative path.

## Stage 1: Fix notify-pr-discord.js path in agent-pipeline.Jenkinsfile

### Description

In `shared/agent-pipeline.Jenkinsfile` line 81, the Discord notification call uses `../shared/notify-pr-discord.js`. This `sh` step runs from the Jenkins workspace root as a separate Groovy `sh` call, so `../` goes above the workspace root and the module is not found.

The fix is to change `../shared/notify-pr-discord.js` to `shared/notify-pr-discord.js`, consistent with how `majordomo/Jenkinsfile` calls the same script.

### Acceptance Criteria

- `shared/agent-pipeline.Jenkinsfile` line 81 uses `shared/notify-pr-discord.js` (no leading `../`)
- `make test` passes (shellcheck, bats, prompt validation)
