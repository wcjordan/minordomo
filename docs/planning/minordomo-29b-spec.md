# minordomo-29b: Prevent Worker Agents from Closing Beads Tasks Prematurely

## Background

Worker agents (`minordomo-step`) sometimes close their own beads task immediately after
opening a PR. The correct lifecycle is: the task stays `in_progress` until Majordomo's
`sync_pr_merge_status` step detects the merged PR and closes it. Three compounding causes
drive this bug: (1) the `bd prime` SESSION CLOSE PROTOCOL instructs every agent to run
`bd close` before finishing, (2) CLAUDE.md's "Session Completion" section says "Close
finished work", and (3) the worker system prompt has no explicit prohibition against
closing the beads task, so the model fills the silence with training-biased cleanup behavior.
There is also no hard enforcement layer to catch it when the soft instruction fails.

---

## Stage 1: Add explicit prohibition in worker system prompt

### Description

Edit `minordomo-step/system-prompt.md` to make it unambiguous that workers must never
close the beads task. Add the prohibition in two places so it is hard to miss:

1. **Before the Steps section** — add a "Hard Rules" block (or extend any existing one)
   with a rule that says workers must leave the beads task `in_progress` after opening
   a PR. Explain that Majordomo closes it automatically when the PR is merged.

2. **At the end of Step 6 (Open PR)** — add a "Do NOT close the beads task" note directly
   after the `gh pr create` block, so it is adjacent to the action that precedes the
   temptation. Include the reason: Majordomo Step 4 (`sync_pr_merge_status`) detects
   the merged PR and closes the task.

The prohibition should mention `bd close`, `beads-write.sh close`, and any equivalent
command that could close the task, so the model cannot rationalize using an alias.

No other files change in this stage.

### Acceptance Criteria

- `minordomo-step/system-prompt.md` contains an explicit rule prohibiting `bd close`
  (and equivalent) on the beads task ID at any point during a worker run.
- The rule appears both near the top of the prompt (in a rules/hard-rules block) and
  inline at the end of Step 6.
- Each prohibition includes a reason: "Majordomo closes the task via
  `sync_pr_merge_status` when the PR is merged."
- `make test` passes.

---

## Stage 2: Defense-in-depth — block `bd close` in worker/planning contexts

### Description

Even with the prohibition in the system prompt, the model may still occasionally ignore
it. Add a hard enforcement layer by:

1. **Export `AGENT_ROLE` in `shared/setup-workspace.sh`** — set it to `"worker"` for
   worker mode and `"planning"` for planning mode so downstream scripts and hooks can
   detect the agent type. Export it early (before the `cd "${REPO}"`) so it is available
   throughout the agent's lifetime.

2. **Add a guard rule in `shared/pre-bash-guard.sh`** — in the hardcoded guard-only
   section at the bottom of the file (not in the generated section), add a check: if
   `$AGENT_ROLE` is `worker` or `planning`, block any command matching `bd close` or
   `beads-write.sh close`. Write the pattern so it catches common invocations:
   - `bd close <id>`
   - `shared/beads-write.sh close <id>`
   - `"$SHARED/beads-write.sh" close <id>`

   The block message should explain: "bd close not allowed in worker/planning context;
   Majordomo closes beads tasks when the PR is merged."

This guard does not affect Majordomo runs because Majordomo does not set `AGENT_ROLE`
(it does not source `setup-workspace.sh`).

### Acceptance Criteria

- `shared/setup-workspace.sh` exports `AGENT_ROLE` as `worker` for worker mode and
  `planning` for planning mode.
- `shared/pre-bash-guard.sh` blocks `bd close <anything>` and `beads-write.sh close
  <anything>` when `$AGENT_ROLE` is `worker` or `planning`.
- The guard allows those same commands when `AGENT_ROLE` is unset (e.g., Majordomo runs).
- Existing bats tests pass; add at least two new bats tests:
  - `bd close minordomo-123` is blocked when `AGENT_ROLE=worker`
  - `bd close minordomo-123` is allowed when `AGENT_ROLE` is unset
- `make test` passes.
