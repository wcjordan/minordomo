# Root Cause Analysis: Workers Closing Beads Tasks Prematurely

## Issue Summary

`minordomo-step` workers sometimes close their own beads task immediately after opening a PR, before the PR is merged. The correct lifecycle is: task stays `in_progress` until Majordomo's `sync_pr_merge_status` step detects the merged PR and closes it.

## Root Causes (multiple, compounding)

### 1. `bd prime` SESSION CLOSE PROTOCOL in every session
The `bd prime` startup hook (loaded via `SessionStart` in every Claude Code session) emits a "SESSION CLOSE PROTOCOL" block instructing the agent to run `bd close <id>` before declaring done. Workers load this hook, see the session close protocol, and infer that closing the active beads task is expected.

### 2. CLAUDE.md "Session Completion" section
`CLAUDE.md` (loaded in every agent context) has a "Session Completion" section that says "Close finished work, update in-progress items." Workers see this and may treat their beads task as "finished work" once they've opened a PR.

### 3. No explicit prohibition in worker system prompt
`minordomo-step/system-prompt.md` is silent on the topic of beads task closure. It describes 6 steps (read task, read spec, implement, test, commit/push, open PR) with no instruction about what happens to the beads task after Step 6. Claude fills the silence with training-biased behavior: "work is done → close the task."

### 4. No enforcement layer
Even if the system prompt had a prohibition, the pre-bash-guard does not block `bd close` in worker contexts. There is no hard constraint to back up a soft prohibition.

## Lifecycle That Should Happen

1. Majordomo Step 8 claims the beads task (`bd update --claim`) before triggering the worker
2. Worker runs, opens PR, task stays `in_progress`
3. Human merges the PR
4. Majordomo Step 4 (`sync_pr_merge_status`) finds the merged PR via `check-pr-merged.sh`, then calls `beads-write.sh close "<task_id>"`

## Recovery Gap

If a worker closes the task before the PR is merged, Majordomo Step 4 will NOT detect it because it only queries `in_progress` tasks. The bead stays closed even though the feature branch may still be incomplete. This is a second-order problem — the fix targets the root cause, but an eventual recovery sweep would be useful.

## Key Files

- `minordomo-step/system-prompt.md` — worker agent instructions (needs prohibition)
- `shared/pre-bash-guard.sh` — command-level enforcement (needs guard rule)
- `shared/setup-workspace.sh` — exports env vars for agent context; good place to export `AGENT_ROLE`
- `shared/safety-rules.yaml` — source of truth for generated guard rules (non-generated hardcoded rules also live in the guard)
- `majordomo/system-prompt.md` Step 4 — where correct beads closure happens (via `beads-write.sh close`)
- `shared/check-pr-merged.sh` — checks if the task PR has merged; used by Majordomo Step 4
