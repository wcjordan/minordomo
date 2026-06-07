# Interactive Step Agent with Discord Q&A

Plan for replacing the fire-and-forget `claude -p` invocation in minordomo-step with an interactive session that can pause and ask questions in Discord when blocked.

Delivered as two independent stories, each merged to main separately.

---

## Motivation

The current minordomo-step agent uses `claude -p` (non-interactive). When it hits an unresolvable blocker it invokes the needs-input protocol: labels the GH issue, posts a comment, and resets the beads task to open — effectively abandoning the run. A human must then re-trigger the job after answering the question.

The goal is to keep the agent running and route questions directly to Discord, so Claude can continue as soon as a human replies — no re-trigger needed.

---

## Architecture Overview

Claude runs interactively inside a synchronous tmux session on the Jenkins worker (tmux provides the TTY that interactive mode requires; running synchronously means the Jenkins `sh` step blocks until tmux exits and exit codes propagate naturally). A Claude Code `Stop` hook fires after every assistant turn. The hook reads Claude's last message and branches:

- **No `NEEDS_INPUT:` prefix** → hook exits immediately, injecting `"Confirmed, please proceed."` back into Claude via the asyncRewake mechanism. Claude continues autonomously.
- **`NEEDS_INPUT:` prefix** → hook posts the question to Discord as a new message and opens a thread on it. It polls the thread every 30 seconds. When a human replies in the thread, the hook injects the reply into Claude via asyncRewake. Claude continues.

```
┌─────────────────────────────────────────────────────┐
│  Jenkins worker (no build timeout)                  │
│                                                     │
│  tmux new-session (synchronous, provides TTY)       │
│  └── claude (interactive)                           │
│       ├── works autonomously (tools, commits, PR)   │
│       └── Stop hook fires after each turn           │
│            ├── no NEEDS_INPUT → "Confirmed, proceed"│
│            └── NEEDS_INPUT → Discord thread         │
│                                 ↕ poll 30s          │
│                             Human replies           │
└─────────────────────────────────────────────────────┘
```

### asyncRewake

The Stop hook is configured with `asyncRewake: true`. Claude does not block waiting for the hook — it enters an idle state after each turn. The hook runs in the background with no timeout. When the hook exits with code `2`, Claude wakes up and receives the hook's stdout as its next instruction.

### Discord threads

Each `NEEDS_INPUT:` question creates a new Discord thread. The human replies directly in that thread. The hook only polls the specific thread it created, so multiple concurrent step-agent runs never interfere with each other.

### NEEDS_INPUT convention

The system prompt instructs Claude: when you cannot proceed without human input, begin your response with `NEEDS_INPUT:` followed by your question. In all other cases, continue autonomously without this prefix.

### Feature flag

An `INTERACTIVE_MODE` boolean build parameter in `minordomo-step/Jenkinsfile` controls which invocation path runs:

- **`INTERACTIVE_MODE=false` (default):** existing `claude -p --output-format json` behavior, unchanged. Log analysis scripts read from stdout as today.
- **`INTERACTIVE_MODE=true`:** tmux-based invocation, Stop hook active, log analysis scripts read from transcript JSONL via `--transcript` flag.

`minordomo-plan` is unaffected — it always uses the old invocation and calls log scripts with the existing interface.

---

## Log Analysis Scripts

`shared/check-run-errors.py` and `shared/report-token-usage.py` currently read `claude -p` JSON from stdin. Both are updated to accept a `--transcript <path>` flag that reads the Claude Code transcript JSONL instead. When `--transcript` is not passed, existing stdin behavior is preserved (backwards compatible for `minordomo-plan`).

---

## Discord Bot Requirements

A Discord bot (separate from the existing outbound webhook) is required to post messages, create threads, and read replies.

Required bot permissions:
- `Send Messages`
- `Create Public Threads`
- `Send Messages in Threads`
- `Read Message History`

Two secrets are needed in Jenkins (wired via a separate `gcp-setup` GH issue):
- `DISCORD_BOT_TOKEN`
- `DISCORD_CHANNEL_ID`

---

## Story 1: Interactive Foundation (no Discord Q&A)

Introduces tmux-based invocation, the Stop hook, and the feature flag. When the agent needs human input it falls back to the existing needs-input protocol (GH issue comment + exit) — same behaviour as today. No Discord bot required.

---

## Stage 1: Feature flag and tmux invocation

### Description

Add an `INTERACTIVE_MODE` build parameter to `minordomo-step/Jenkinsfile`. When true, run `claude` in a synchronous tmux session (providing a TTY) instead of `claude -p`. When false, existing behaviour is unchanged. Update `shared/agent-pipeline.Jenkinsfile` to branch on the flag for the claude invocation step. Remove the build timeout from `minordomo-step/Jenkinsfile` (only when interactive mode is active; keep it for the old path).

### Acceptance Criteria

- `INTERACTIVE_MODE=false` runs exactly as today — no behaviour change.
- `INTERACTIVE_MODE=true` starts a tmux session, runs `claude` interactively, and the Jenkins step exits with Claude's exit code when the session ends.
- `make test` (shellcheck + bats) passes.

---

## Stage 2: Stop hook with auto-confirm and needs-input fallback

### Description

Write `shared/claude-stop-hook.js`. The script:

1. Parses hook JSON from stdin and reads the last assistant message from the transcript at `transcript_path`.
2. If no `NEEDS_INPUT:` prefix: writes `"Confirmed, please proceed."` to stdout and exits code `2` (asyncRewake — Claude wakes and continues).
3. If `NEEDS_INPUT:` prefix: calls `shared/apply-needs-input.sh` with the question text (existing needs-input flow — GH issue comment, beads reset, exit). This preserves today's blocked-agent behaviour as the Story 1 fallback.

Update `shared/agent-settings.json` to add the Stop hook with `asyncRewake: true`, pointing to `shared/claude-stop-hook.js`. Update `minordomo-step/system-prompt.md` to describe the `NEEDS_INPUT:` convention and remove the instructions that directly invoke `apply-needs-input.sh` (the hook now handles that path).

### Acceptance Criteria

- When Claude's last message has no `NEEDS_INPUT:` prefix, the hook exits immediately with `"Confirmed, please proceed."` and Claude continues.
- When Claude's last message starts with `NEEDS_INPUT:`, the hook invokes `apply-needs-input.sh` and exits 0 (run ends, GH issue labelled, beads reset — same as today).
- Hook script passes shellcheck. Manual test: run `claude-stop-hook.js` with a dummy transcript file and verify both branches.
- `make test` passes.

---

## Stage 3: Update log analysis scripts for transcript mode

### Description

Add `--transcript <path>` flag to `shared/check-run-errors.py` and `shared/report-token-usage.py`. When passed, each script reads the Claude Code transcript JSONL file at that path instead of stdin. When not passed, existing stdin behaviour is unchanged.

Update `shared/agent-pipeline.Jenkinsfile` to call both scripts with `--transcript <transcript_path>` when `INTERACTIVE_MODE=true`. When `INTERACTIVE_MODE=false`, call them as today (no flag change).

### Acceptance Criteria

- `minordomo-plan` pipeline (always `INTERACTIVE_MODE=false`) calls scripts with no new flags — no behaviour change.
- `minordomo-step` with `INTERACTIVE_MODE=true` calls scripts with `--transcript`; scripts parse the transcript JSONL correctly.
- Both scripts still accept stdin input when `--transcript` is absent.
- `make test` passes.

---

## Story 2: Discord Q&A Integration

Completes the interactive loop. Replaces the `apply-needs-input.sh` fallback in the Stop hook with live Discord thread Q&A. Requires `DISCORD_BOT_TOKEN` and `DISCORD_CHANNEL_ID` to be wired in Jenkins (tracked in a separate `gcp-setup` GH issue).

---

## Stage 1: Discord thread posting and reply polling

### Description

Extend `shared/claude-stop-hook.js` to replace the `apply-needs-input.sh` fallback with Discord Q&A:

1. Extract the question text (everything after `NEEDS_INPUT:`).
2. POST the question to `DISCORD_CHANNEL_ID` using `DISCORD_BOT_TOKEN` via the Discord REST API.
3. Create a public thread on that message.
4. Poll the thread every 30 seconds for new non-bot messages using `GET /channels/{thread_id}/messages`.
5. When a reply arrives, write it to stdout and exit code `2` (asyncRewake — Claude wakes with the reply as its next instruction).

Uses the `discord.js` dependency already present in the container. If `DISCORD_BOT_TOKEN` or `DISCORD_CHANNEL_ID` are absent, log a warning and fall back to `apply-needs-input.sh` (graceful degradation).

### Acceptance Criteria

- When `NEEDS_INPUT:` is detected and bot credentials are present: question posted to Discord, thread created, hook blocks polling, reply injected into Claude on receipt.
- When credentials are absent: warning logged, falls back to `apply-needs-input.sh`.
- Thread isolation: two concurrent hook instances polling different threads do not receive each other's replies.
- `make test` passes.

---

## Stage 2: Credential wiring and end-to-end validation

### Description

Wire `DISCORD_BOT_TOKEN` and `DISCORD_CHANNEL_ID` into the Jenkins credential store and inject them into minordomo-step builds. This depends on the `gcp-setup` GH issue being completed first.

Update `minordomo-step/Jenkinsfile` to inject both secrets as environment variables when `INTERACTIVE_MODE=true`. Validate end-to-end with a test run: trigger a minordomo-step build with `INTERACTIVE_MODE=true`, observe a `NEEDS_INPUT:` question appear as a Discord thread, reply, and confirm Claude continues.

### Acceptance Criteria

- `DISCORD_BOT_TOKEN` and `DISCORD_CHANNEL_ID` available as env vars in minordomo-step builds.
- End-to-end test run: question appears in Discord thread, reply resumes Claude.
- `INTERACTIVE_MODE=false` builds unaffected (no credential injection needed).
- `make test` passes.

---

## Resolved Design Decisions

| Question | Resolution |
|---|---|
| tmux exit detection | Run `tmux new-session` synchronously (no `-d`); Jenkins `sh` step blocks naturally and exit code propagates. |
| transcript_path in asyncRewake | Expected to be present (common input field for all hook events); verify early with a minimal logging hook before full implementation. |
| Log capture | Read Claude Code's transcript JSONL via `--transcript` flag instead of capturing stdout; backwards-compatible with existing stdin mode. |
| Existing needs-input calls | Story 1: hook calls `apply-needs-input.sh` as fallback. Story 2: replaced by Discord Q&A. `apply-needs-input.sh` kept for `minordomo-plan`. |
