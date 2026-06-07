# Interactive Step Agent with Discord Q&A

Plan for replacing the fire-and-forget `claude -p` invocation in minordomo-step with an interactive session that can pause and ask questions in Discord when blocked.

---

## Motivation

The current minordomo-step agent uses `claude -p` (non-interactive). When it hits an unresolvable blocker it invokes the needs-input protocol: labels the GH issue, posts a comment, and resets the beads task to open — effectively abandoning the run. A human must then re-trigger the job after answering the question.

The goal is to keep the agent running and route questions directly to Discord, so Claude can continue as soon as a human replies — no re-trigger needed.

---

## Architecture Overview

Claude runs interactively inside a tmux session on the Jenkins worker (tmux provides the TTY that interactive mode requires). A Claude Code `Stop` hook fires after every assistant turn. The hook reads Claude's last message and branches:

- **No `NEEDS_INPUT:` prefix** → hook exits immediately, injecting `"Confirmed, please proceed."` back into Claude via the asyncRewake mechanism. Claude continues autonomously.
- **`NEEDS_INPUT:` prefix** → hook posts the question to Discord as a new message and opens a thread on it. It polls the thread every 30 seconds. When a human replies in the thread, the hook injects the reply into Claude via asyncRewake. Claude continues.

```
┌─────────────────────────────────────────────────────┐
│  Jenkins worker (no build timeout)                  │
│                                                     │
│  tmux session                                       │
│  └── claude (interactive)                           │
│       ├── works autonomously (tools, commits, PR)   │
│       └── Stop hook fires after each turn           │
│            ├── no NEEDS_INPUT → "Confirmed, proceed"│
│            └── NEEDS_INPUT → Discord thread         │
│                                 ↕ poll 30s          │
│                             Human replies           │
└─────────────────────────────────────────────────────┘
```

---

## Key Mechanisms

### asyncRewake

The Stop hook is configured with `asyncRewake: true`. This means:

- Claude does not block waiting for the hook — it enters an idle state after each turn.
- The hook runs in the background with no timeout.
- When the hook exits with code `2`, Claude wakes up and receives the hook's stdout as its next instruction.
- When the hook exits with code `0`, Claude stays idle (used for the non-NEEDS_INPUT path only if we want to truly pause — but we use code `2` immediately to keep Claude moving).

### Discord threads

Each `NEEDS_INPUT:` question creates a new Discord thread. The human replies directly in that thread. The hook only polls the specific thread it created, so multiple concurrent step-agent runs never interfere with each other.

### NEEDS_INPUT convention

The system prompt instructs Claude: when you cannot proceed without human input, begin your response with `NEEDS_INPUT:` followed by your question. In all other cases, continue autonomously without this prefix.

---

## Components

### New: `shared/discord-stop-hook.js`

Node.js script invoked by the Stop hook. Responsibilities:

1. Parse hook JSON from stdin to get `transcript_path`.
2. Read the transcript JSONL file and extract the last assistant message.
3. Check whether the message starts with `NEEDS_INPUT:`.
4. **No prefix path:**
   - Write `{"continue": true, "reason": "Confirmed, please proceed."}` to stdout.
   - Exit code `2`.
5. **NEEDS_INPUT path:**
   - Extract the question text (everything after `NEEDS_INPUT:`).
   - POST to the Discord channel (`DISCORD_CHANNEL_ID`) using the bot token (`DISCORD_BOT_TOKEN`) to create a message.
   - Open a thread on that message via the Discord API.
   - Poll the thread every 30 seconds for new non-bot messages.
   - When a reply arrives, write it to stdout and exit code `2`.

Uses the existing `discord.js` dependency already in the container.

### Changed: `shared/agent-settings.json`

Add a Stop hook entry:

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "node shared/discord-stop-hook.js",
        "asyncRewake": true
      }
    ]
  }
]
```

### Changed: `minordomo-step/Jenkinsfile`

- Remove the build timeout (currently set in the pipeline options block).
- Replace the `claude -p` invocation with a tmux-based interactive session:
  1. Start a detached tmux session running `claude`.
  2. Send the system prompt as the initial message via `tmux send-keys`.
  3. Wait for the tmux session to exit (Claude finishes the task).
  4. Capture the exit code and session log for downstream steps.

### Changed: `shared/agent-pipeline.Jenkinsfile`

- Remove or gate the `--output-format json` flag (not valid in interactive mode).
- Adjust log capture to read from the tmux session's output rather than claude's stdout.
- Keep downstream steps (beads dolt push, notify-pr-discord) unchanged.

### Changed: `minordomo-step/system-prompt.md`

Add a section explaining the `NEEDS_INPUT:` convention and replacing the current needs-input protocol description:

> **Asking for Human Input**
>
> If you reach a point where you cannot proceed without human input, begin your response with `NEEDS_INPUT:` followed by your question. Do not apply the `needs-input` GitHub label or reset the beads task — the pipeline will route your question to Discord and resume automatically when a human replies.
>
> Only use `NEEDS_INPUT:` when genuinely blocked. In all other cases, continue autonomously.

### New: GH issue in `gcp-setup`

Wire two new secrets into the Jenkins credential store and inject them into minordomo-step builds:

| Secret | Description |
|---|---|
| `DISCORD_BOT_TOKEN` | Bot token; requires `Send Messages` + `Read Message History` + `Create Public Threads` permissions |
| `DISCORD_CHANNEL_ID` | ID of the Discord channel where questions are posted |

The bot must be invited to the target channel.

---

## Discord Bot Setup

A Discord bot (separate from the existing webhook) is required because reading thread replies needs bot-level access. The existing `discord-send.js` webhook remains for PR notifications — this is additive.

Required bot permissions:
- `Send Messages`
- `Create Public Threads`
- `Send Messages in Threads`
- `Read Message History`

---

## Implementation Order

1. **Create `gcp-setup` GH issue** — unblocks credential wiring in parallel with code changes.
2. **Write `shared/discord-stop-hook.js`** — core logic; can be tested locally with a dummy transcript.
3. **Update `shared/agent-settings.json`** — add the Stop hook.
4. **Update `minordomo-step/system-prompt.md`** — add `NEEDS_INPUT:` convention.
5. **Update `minordomo-step/Jenkinsfile`** — remove timeout, switch to tmux-based invocation.
6. **Update `shared/agent-pipeline.Jenkinsfile`** — adjust log capture.

Steps 2–4 can be done in parallel. Steps 5–6 depend on understanding the final tmux invocation shape.

---

## Open Questions

- **tmux exit detection:** The Jenkins pipeline needs to know when Claude's tmux session ends and with what exit code. Options: `tmux wait-for -S done` with a signal from the Claude session, or polling `tmux has-session` in a loop. Needs investigation.
- **Transcript path in asyncRewake:** Confirm that `transcript_path` is provided in the hook JSON input when asyncRewake is used (vs. only in synchronous hook invocations).
- **Log capture:** The current pipeline passes Claude's stdout to `check-run-errors.py` and `report-token-usage.py`. In interactive/tmux mode the log source changes — determine whether to pipe tmux output or use Claude's `--output-dir` flag if available.
- **Existing needs-input calls:** `shared/apply-needs-input.sh` is still invoked from the system prompt for the old flow. Once this is shipped the system prompt should remove those instructions; the script can be left in place for the planning agent.
