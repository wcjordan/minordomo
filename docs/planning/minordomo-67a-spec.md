# Plan: Post a Message to Discord Whenever Human Input Is Requested

## Overview

When the planning agent asks a question and triggers the Questions Path, it resets its beads task and exits 0 — but nothing notifies the human to go look at the GitHub issue. This feature adds a Discord notification at that moment.

**Scope**: Planning agent Questions Path only. The worker's Needs Input Flow exits 1, which causes the `sh` step to throw in Jenkins and skip subsequent steps including the Discord notifier. Worker coverage is a follow-up.

**Discord message format**: `"Human input requested: <gh_issue_url>"`

---

## Stage 1: Update notify-pr-discord.js to send notifications on needs-input

### Description

Add detection logic to `shared/notify-pr-discord.js` so it sends a Discord message when the planning agent emits a `beads_status_update` step with `reason: "needs_input"` and a `gh_issue_url` field. Message format: `"Human input requested: <gh_issue_url>"`.

Add bats tests in `test/bats/notify-pr-discord.bats` covering:
- Sends message when `beads_status_update` step has `reason: "needs_input"` and `gh_issue_url`
- Does not send when `beads_status_update` step has `reason: "needs_input"` but no `gh_issue_url`
- Existing PR notification tests still pass (no regression)

This stage is inert in production until Stage 2 lands (planning agent doesn't yet emit `gh_issue_url`).

### Acceptance Criteria

- `notify-pr-discord.js` sends `"Human input requested: <gh_issue_url>"` when the run log contains a `beads_status_update` step with `reason: "needs_input"` and a `gh_issue_url` field
- If `gh_issue_url` is absent on the step, the notifier silently skips (no message, no error)
- All existing `notify-pr-discord.bats` tests continue to pass
- New bats tests for the needs-input case are added and pass
- `make test` passes

---

## Stage 2: Update planning agent system prompt to emit gh_issue_url in beads_status_update step

### Description

Update `minordomo-plan/system-prompt.md` to include `gh_issue_url` in the `beads_status_update` run log step when emitting the Questions Path outcome. The planning agent already knows `gh_issue_url` (extracted from the beads task description in Step 1), so this is purely a run log format change.

Specifically, update:
1. The Questions Path instructions to emit `gh_issue_url` in the step
2. The Run Log Format section's `beads_status_update` example to show the new field

Also update the system prompt you are currently running from (the planning agent prompt in this workspace) to match, since both copies must stay in sync.

### Acceptance Criteria

- `minordomo-plan/system-prompt.md` shows `"gh_issue_url"` in the `beads_status_update` step example
- The Questions Path instructions explicitly instruct the agent to include `gh_issue_url` in the `beads_status_update` step
- The system prompt the planning agent uses (in this workspace, which is the same file) reflects these changes
- `make test` passes (prompt validation checks)
